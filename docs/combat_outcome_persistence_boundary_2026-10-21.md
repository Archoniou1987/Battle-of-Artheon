# Battle of Artheon — Combat Outcome & Persistence Boundary (2026-10-21)

## Verified contracts in source (CI for this package pending)

**Arena is a fresh training duel upon entry.** `scenes/main/main.gd::_open_arena_screen` constructs a new `ArenaScreen`; `ui/arena/arena_screen.gd::_start_combat_session` constructs a new `ArenaCombatSession`. The combat history, ability cooldowns, timed EFF, Tempo stun, NPC HP and active combat RNG are NOT part of the existing player save. Do **not** describe this system as resumable combat or silently auto-resume a training duel without a product decision.

**Resources persist:** the UI calls `CharacterState.commit_combat_resources` only for the owned combatant; a successful command writes the actual resolved visible HP and Mana back to the player. `main.gd` saves these resources with schema v1 and restores them when the village restarts. This preserves real death at zero HP and does not restore health on a training restart. Offline regeneration remains a separate out-of-combat rule.

**World consequences are a different boundary:** normal map encounters use a `CombatSimulator` verdict (`winner_id`/`loser_id`) passed to `MapCombatOutcomeService`. The service marks the persistent NPC dead, removes it from the map and assigns once-only loot to an `EncounterLootPool`. That should not be conflated with the Arena-only `winner:player` / `winner:enemy` labels, nor should the training dummy generate map loot.

## New regression gates

- `tests/ui/arena_terminal_persistence_runner.gd`: real victory and defeat through Village -> ArenaScreen -> ArenaCombatSession -> CombatEngine -> CharacterState -> progression JSON -> restarted Village, including canonical event lineage, disabled End Turn after terminal outcome, rejected replay without mutation, fresh training NPC on reentry, and irreversible 0-HP lockout until an explicit recovery mechanism.
- `tests/map/map_real_duel_reward_chain_runner.gd`: actual map encounter -> engine duel verdict -> rejected false victory -> NPC death -> single eligible loot entry -> second verdict rejected -> serialized pool -> claim exactly once. No synthetic `winner_id` is passed to the service in the successful path.
- `ui/arena/arena_screen.gd`: a rejected input can re-enable End Turn **only** if the current battle outcome is ongoing and the player has positive, non-finalized HP. Fixes an erroneous enabled button after victory or defeat.

## Scope / next architecture decision

This checkpoint does **not** introduce saved mid-battle resumability, a new persistent battle schema, PvP rewards, or training dummy loot. Introducing resumable expeditions requires a separately versioned combat snapshot covering RNG state, character/NPC identity and equipment, active round status, event log, ABI cooldowns, EFF lifecycle, Tempo, elixir cooldowns, map encounter membership, and safe validation of stale/corrupt saves. Keep that distinct from the already shipping CharacterState progression v1 save.

All new tests are attached to the existing **manual** `ABI Branch Tests` gate. The code is committed; new CI has **not** yet been verified on this revision.
