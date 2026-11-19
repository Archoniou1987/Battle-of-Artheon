# Solo combat session manifest — start-before-battle and launch recovery

The last verified successful ABI run is #289 (39641145616) on
30c035e1df5db70c8cbab98c03a79cb88ccb5f99.

New `SoloCombatSessionManifest` provides a durable, SHA-256-verified
`user://` record containing the encounter ID, expedition/player identities,
canonical expedition save path, terminal world snapshot path, combat
checkpoint path and pre-battle expedition revision.

`begin(...)` must execute **before** starting checkpointed combat.
It refuses another pending combat and requires a valid saved expedition.
`recover_on_launch(...)` must execute **before** map actions:

- No manifest: ordinary expedition load can proceed.
- Manifest with no terminal world snapshot: return
  `resume_combat_checkpoint` and do not discard or modify the save.
  The existing combat checkpoint owner must resume the battle.
- Manifest with a verified terminal snapshot: call the existing
  idempotent `ExpeditionSaveService.recover_pending_combat` and
  remove the manifest only after the expedition publication succeeds.
- A changed base revision, conflicting receipt or corrupted manifest
  is rejected without overwriting the expedition.

The real two-fight integration runner now creates a manifest prior to
each fight, simulates launch before the terminal snapshot exists,
then recovers terminal outcomes after an interrupted publication.
It verifies the manifest was removed after success and a second
launch does not reapply rewards.

**Not yet automatic app entrypoint wiring:** The manager is a callable
startup boundary. The playable map/scene entrypoint still needs to invoke
`recover_on_launch`, reconcile NPCs and resume checkpointed combat when
indicated, before enabling input. DebugMapViewer is still a synthetic
world and should not silently take ownership of production saves.

This new package awaits CI.
