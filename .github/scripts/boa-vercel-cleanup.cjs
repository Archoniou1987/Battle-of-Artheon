'use strict';
const crypto = require('node:crypto');
const TEAM = 'team_3X6DttKAdVaDmYJVv5SYCcsA';
const PROJECT = 'prj_O8XlqWc2OFjUvp9Z1RojYFiMOVCl';
const DOMAIN = 'battle-of-artheon.vercel.app';
const SECOND_BRANCH = 'feature/equipment-instance-chain';
const CUTOFF = Date.parse('2026-10-23T14:12:37.224Z');
const token = process.env.VERCEL_TOKEN;
const mode = process.env.CLEANUP_MODE || 'plan';
const approval = (process.env.APPROVED_PLAN_SHA256 || '').trim().toLowerCase();
if (!token) throw new Error('Missing secret VERCEL_TOKEN');
if (!['plan', 'delete'].includes(mode)) throw new Error('Invalid mode');
async function api(path, method = 'GET') {
  const url = new URL('https://api.vercel.com' + path);
  url.searchParams.set('teamId', TEAM);
  const response = await fetch(url, {
    method,
    headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' },
    signal: AbortSignal.timeout(20000),
  });
  const body = await response.text();
  if (!response.ok) throw new Error(method + ' ' + url.pathname + ': HTTP ' + response.status + ' ' + body.slice(0, 400));
  return body ? JSON.parse(body) : {};
}
async function listAll() {
  const result = [], seen = new Set();
  let until;
  for (let page = 0; page < 30; page++) {
    let path = '/v6/deployments?projectId=' + PROJECT + '&limit=100';
    if (until !== undefined) path += '&until=' + until;
    const data = await api(path);
    if (!Array.isArray(data.deployments)) throw new Error('Unexpected deployment response');
    if (data.deployments.length === 0) return result;
    for (const d of data.deployments) {
      if (!d.id || !Number.isSafeInteger(d.created) || !d.meta?.githubCommitRef ||
          d.name !== 'battle-of-artheon' || d.target !== 'production') {
        throw new Error('Unexpected deployment metadata; abort safely');
      }
      if (!seen.has(d.id)) { seen.add(d.id); result.push(d); }
    }
    const next = data.pagination?.next;
    if (!next) return result;
    if (next === until) throw new Error('Pagination did not advance');
    until = next - 1;
  }
  throw new Error('Exceeded pagination safety limit');
}
async function listAliases() {
  const data = await api('/v4/aliases?projectId=' + PROJECT + '&limit=100');
  if (!Array.isArray(data.aliases) || data.pagination?.next) throw new Error('Aliases unavailable or incomplete');
  if (!data.aliases.some(a => a.alias === DOMAIN)) throw new Error('Production domain missing');
  for (const a of data.aliases) {
    if (!a.deploymentId || a.projectId !== PROJECT) throw new Error('Unexpected alias data');
  }
  return data.aliases;
}
function sha(ids) { return crypto.createHash('sha256').update(ids.join('\n')).digest('hex'); }
async function plan() {
  const [all, aliases, prod] = await Promise.all([
    listAll(), listAliases(), api('/v13/deployments/' + DOMAIN),
  ]);
  if (!prod.id || prod.project?.id !== PROJECT || prod.readyState !== 'READY') throw new Error('Production identity/status mismatch');
  const ordered = all.slice().sort((a,b)=>b.created-a.created);
  const secondary = ordered.find(d => d.meta.githubCommitRef === SECOND_BRANCH && d.state === 'READY');
  if (!secondary || ordered.length < 11) throw new Error('Not enough deployments or missing backup branch');
  const keep = new Set(ordered.slice(0,10).map(d=>d.id));
  keep.add(secondary.id); keep.add(prod.id);
  for (const a of aliases) keep.add(a.deploymentId);
  const candidates = ordered.filter(d =>
    !keep.has(d.id) && d.state === 'READY' && d.created <= CUTOFF &&
    ['feature/character-inventory-ui-v1', SECOND_BRANCH].includes(d.meta.githubCommitRef)
  );
  if (keep.size < 11) throw new Error('Backup protection invariant failed');
  const ids = candidates.map(d=>d.id).sort();
  const digest = sha(ids);
  console.log('Team: ' + TEAM + '; project: ' + PROJECT);
  console.log('Live production: ' + prod.id);
  console.log('Protected IDs (' + keep.size + '): ' + [...keep].join(', '));
  console.log('Candidate count: ' + ids.length + '; PLAN_SHA256: ' + digest);
  console.log('Candidate IDs:\n' + ids.join('\n'));
  if (process.env.GITHUB_STEP_SUMMARY) {
    const fs = require('node:fs');
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,
      '## BoA deployment cleanup\n\nMode: **' + mode + '**\n\n' +
      'Production: ' + prod.id + '\n\nProtected: **' + keep.size +
      '**\n\nCandidates: **' + ids.length + '**\n\nPLAN_SHA256: ' + digest + '\n');
  }
  return { candidates, digest, keep, productionId:prod.id };
}
async function main() {
  const first = await plan();
  if (mode === 'plan') { console.log('PLAN ONLY. No deletion was performed.'); return; }
  if (process.env.CONFIRM_DELETE !== 'DELETE_OLD_BOA_DEPLOYMENTS') throw new Error('Missing exact destructive confirmation phrase');
  if (!/^[a-f0-9]{64}$/.test(approval) || first.digest !== approval) throw new Error('Approved SHA256 differs from current candidates. Run plan again.');
  if (first.candidates.length < 1 || first.candidates.length > 126) throw new Error('Unexpected candidate count; abort');
  const second = await plan();
  if (second.digest !== approval || second.productionId !== first.productionId) throw new Error('Deployment/alias state changed; abort');
  for (const d of second.candidates) {
    if (second.keep.has(d.id) || d.id === second.productionId || d.created > CUTOFF) throw new Error('Protection invariant violated');
    await api('/v13/deployments/' + encodeURIComponent(d.id), 'DELETE');
    console.log('Deleted: ' + d.id);
  }
  console.log('Delete requests completed: ' + second.candidates.length);
  const live = await api('/v13/deployments/' + DOMAIN);
  if (live.id !== second.productionId || live.readyState !== 'READY') throw new Error('ALERT: production changed after cleanup');
  console.log('Production verified READY and unchanged: ' + live.id);
}
main().catch(e=>{ console.error(e.message); process.exitCode=1; });
