# Solo live NPC battle: real combat engine, checkpointed rounds (2026-10-21)

Last confirmed green: ABI #297, run 39672044226, at 12637b5f5210a72d730d3d70c963538a3dbd4acb.

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
- If the application closes mid-battle, the precombat manifest blocks
  map activity, but automatic checkpoint resurrection into the scene
  is not implemented yet.
- This release does not yet implement clickable ground-loot pickup
  on the playable map (ground loot is stored durably by the core).
- No manual Actions run was initiated. Await ABI before promoting
  this integration to verified.

The next packages must focus on full round commands, defeat,
checkpoint resume, and ground pickup, not new combat arithmetic.
