# Solo live NPC battle: real combat engine, checkpointed rounds (2026-10-21)

Last confirmed green: ABI #298, run 39673919754, at cf0ffd0e69d6485a888933679bda2a937cb7cd05. The subsequent restart/resume changes need a new manual ABI run.

First integration into the playable Solo map:
- Clicking a neighboring NPC starts `SoloLiveNpcCombat.start`.
- Registers `SoloCombatSessionManifest` before entering the NPC's hex.
- Uses `CharacterCombatBuilder.build`, `NpcRepository`,
  `HexMapTurnService.move_player` and
  `begin_resumable_group_combat`; not a test fixture or scripted victory.
- Generates stable encounter-specific checkpoint, receipt and terminal
  world snapshot paths; existing artifacts are never discarded on contact.
- `GroupCombatSimulator.run_round()` performs one actual round at a
  time; its checkpoint must succeed before the UI advances.
- On victory, `HexMapTurnService.finalize_group_victory_atomic` performs
  genuine settlement, dead-NPC tombstones and ground loot migration,
  writes the verified terminal snapshot, then the manifest publishes
  it to the cross-encounter expedition save. All references reuse
  the same live character and repository.
- Map movement and return are blocked while a battle manifest exists.

New early ABI runner `tests/map/solo_live_npc_combat_runner.gd` proves
adjacent contact is required, a canonical player and genuine NPC are
present in the combat engine, precombat manifest blocks a second
fight, and a real round is checkpointed without corrupting the
canonical expedition file.

**Important limitations**:
- This is the first integrated combat control, not yet the full
  five-zone Arena presentation. Automatic basic attacks are executed
  by GroupCombatSimulator for both sides; manual attacks, blocks,
  elixirs and ABI input are not routed through this map UI yet.
- A defeat currently returns `defeat_pending_resolution` and blocks
  further actions rather than inventing player-death consequences.
  That needs an explicit map-defeat/recovery path.
- Closing after a completed round can now restore the same encounter from
  `SoloLiveMapSession.open_pending` and `SoloLiveNpcCombat.resume`.
  The village presents a **Продолжить бой** action for that state; the map
  restores the latest checkpoint without replaying earlier rounds.
  A missing or corrupt checkpoint fails closed and is not replaced by a new fight.
- This release does not yet implement clickable ground-loot pickup
  on the playable map (ground loot is stored durably by the core).
- The live-combat base passed ABI #298. The newer scene/gate resume and
  terminal-checkpoint regression package has not yet passed a fresh CI run.

## Restart/publish invariants (new package, pending CI)

- The canonical expedition file remains the *pre-battle* owner while the
  manifest and round checkpoints exist; no map movement or town return.
- `begin_resumable_group_combat` checks the immutable roster/loadout fingerprint
  and restores the same NPC cohort, HP, round, event counters and RNG state.
- If a restored checkpoint is already terminal, `SoloLiveNpcCombat.play_round`
  **must not call** `run_round` again: it publishes the existing winner through
  atomic world settlement and `SoloCombatSessionManifest.recover_on_launch`.
- A published terminal world snapshot is idempotent: a second publication
  returns `already_published` without recreating rewards or changing the save.
- The map return button and movement remain disabled on any unresolved manifest,
  including failed checkpoint validation; no forced reset is supported.
- A crash **before the first completed round checkpoint** currently remains
  blocked intentionally: no round-zero checkpoint can be restored.
- Defeat still needs its own consequence path and is not silently treated
  as a victory or fresh encounter.

New grouped ABI tests:
`tests/map/solo_live_combat_resume_runner.gd` verifies missing/corrupt saves,
identity, roster, round continuity and fail-closed movement;
`tests/map/solo_live_terminal_resume_runner.gd` completes a genuine NPC fight,
stops after the winning checkpoint, resumes it, publishes once, checks the
world ledger, persistent NPC death, ground loot and duplicate-publication guard.

Next packages should focus on player-controlled round commands, defeat
resolution, ground pickup, and full map presentation rather than new combat arithmetic.
