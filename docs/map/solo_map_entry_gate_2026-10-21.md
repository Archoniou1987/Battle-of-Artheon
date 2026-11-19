# Solo entry gate — main village map navigation (2026-10-21)

Previous confirmed green: ABI #290, run 39642711331, commit 9f995ae6d57a7ef87f5f70c34bfcb687c2c8fd96.

`SoloExpeditionLaunchGate.inspect` verifies an existing
`ExpeditionSaveService` save before allowing any map transition.
If a pending `SoloCombatSessionManifest` exists it validates owner
identity before invoking `recover_on_launch`. A missing terminal
snapshot blocks the map with `resume_combat_checkpoint`; corrupt or
unrelated files block instead of being overwritten. A valid terminal
snapshot can publish pending rewards and then reload the authoritative
expedition owner.

The starting village's **Карта** navigation now uses this fail-closed
gate rather than the generic unimplemented-feature popup. It displays
the reason why entering the map is not yet available. This is
deliberate: the main village still stores character progression and
inventory separately under the legacy city save. The expedition
identity and the fully playable map orchestration are not yet wired
to that identity. Opening a synthetic debug map automatically would
silently conflate independent owners.

`tests/map/solo_launch_gate_runner.gd` covers fresh expedition,
verified saved expedition, wrong player, pending checkpoint,
corrupted manifest and failure to bypass the gate. It is placed
early in ABI Branch Tests.

**Remaining:** migration/hand-off of city character and inventory to
one expedition owner, automatic live map/NPC reconstruction, actual
checkpoint resume flow, and unlocking map actions only after all
those steps succeed. New integration is not CI-verified yet.
