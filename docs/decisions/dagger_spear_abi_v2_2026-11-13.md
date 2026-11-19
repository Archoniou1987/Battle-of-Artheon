# Physical dagger archetypes + two-handed spear — ABI v2 (2026-11-13)

Status: **spear slow rebalance implemented on 2026-11-16; new CI pending**.
Scope: DAGGER_ATTACK, DAGGER_DEF, DAGGER_PEN, 2H_SPEAR only. DAGGER_MAGIC unchanged.

| Archetype | ABI 1 | ABI 2 | ABI 3 | ABI 4 |
|---|---|---|---|---|
| Attacking dagger | ABI409 Quick Stab → EFF406 Accuracy | ABI410 Focus → EFF407 crit bonus | ABI411 3 crit-capable strikes → Accuracy | ABI412 Finisher spends Accuracy |
| Defensive dagger | ABI413 Lunge after previous dodge | ABI414 Dance → EFF409 dodge and EFF408 counter charges | ABI415 fan AoE reads counter charges | ABI416 Combo spends charges → EFF410 dodge buff |
| Penetrating dagger | ABI417 hit → EFF401 armour breach | ABI418 at 2+ breach adds more breach / AP | ABI419 hit reads breach → EFF411 damage weaken | ABI420 consumes breach, 20% armour bypass per stack |
| 2H spear | ABI701 on hit → EFF412 Slow; +30% damage if already slowed | ABI702 AoE on hit → EFF412 Slow | ABI703 on Slow: −100 Tempo and consumes Slow | ABI704 on Slow: EFF413 Armour Fracture; retains Slow |

## Single-source constraints
- ITEM v1.2 `data/items/item_generator_v12_rules.json` assigns four ABI IDs to an archetype; off-hand ABI remain inactive.
- ABI catalogue owns costs, base numeric damage, per-10-level improvement and Attack Power coefficient.
- EFF catalogue owns duration, stacking, magnitudes and control reduction.
- CombatEngine owns physical hit, crit, mitigation; PAR232 flows through AttackPowerService only once.
- EFF412 reduces Tempo by 20 per active tick for two rounds; this occurs in canonical RoundOrchestrator timed-EFF phase (not on initial application). Both ABI701 and ABI702 apply EFF412 only on an actual connected hit; defence can dodge/block as defined by CombatEngine. ABI701 damage bonus is calculated only if Slow was active before its hit. ABI703 spends Slow; ABI704 retains Slow. A scheduled stun removes spear Slow, and shared CombatTempoService applies its ordinary immunity/rebound. UI calls it «Замедление».
- Distinct armour-reduction EFF combine additively on the raw armour percentage, before DR. Existing post-DR hammer-zone fracture stays separate.
- Existing 401–408 remain executable only for older references/tests. New generated weapons use 409–420; equipment derives updated loadouts for saved v1.2 daggers without changing their stored rolls.
- Magic daggers, other physical families and passive weapon attacks are not redesigned.

## Balance / verification
- New ABI numeric damage and EFF413 fracture intensity are **provisional**; approved mechanic structure remains authoritative.
- Verify Combat Integration Gate and physical weapon factory before considering implementation complete.
