# Battle of Artheon — World / Settlement / Map Instance foundation

## Purpose

Introduce a **single map model** suitable for local Solo simulation and later authoritative multiplayer. This is the contract foundation, not an active MP implementation or replacement for the existing playable 12×12 Solo map.

## Identity and ownership

- **World**: geographical network of settlements and their roads; settlement travel is separate from map movement.
- **Settlement**: the geographical origin for expeditions; defines biome and minimum access requirements.
- **MapInstance**: one immutable instance ID, independently chosen seed, generator version, settlement, biome, difficulty/access policy, lifecycle, and optional outgoing links.
- **MapState**: mutable NPCs, loot, exploration, positions, and battles; authoritative for the particular map instance.
- **PlayerState**: one character owner with PAR, inventory, current place, timers, and future PvP sanction. Never clone the character into MapState.

The instance ID is never reused, even after the instance closes. Seed reuse is allowed and does not imply shared world state. A map cannot be regenerated in place under an existing ID with a different seed. Retaining or retiring an instance is a lifecycle decision, not a reset-on-town-exit rule.

## Access and transitions

- Maps below level 75 have no open-world PvP. All maps level 75+ are MP-joinable when networking exists, even when generated at random.
- Entry from a settlement requires matching settlement ID and level. Time/crowding rules are future policy, not hard-coded into map identity.
- Each map can expose a special exit to a linked map in the **same settlement region and biome**; travel time is configurable (initial design one minute). Town exit is a *different* operation with its own PvP restrictions.
- In-flight fights, pending item claims, and crash recovery journals must prevent early instance retirement.
- The Solo v1 map stays playable with existing save format and progression until a separately verified migration connects the new map contract.

## Solo / MP persistence

One **data schema**, differing execution authority: local Solo owner now, server-owned shared instances later. No competing Solo/MP map engines. An MP map cannot use the local player's GameState file as its shared authoritative storage. Both player and shared-map changes need an explicitly transactional commit contract for combat, loot and cross-map moves.

Current SoloGameStateService and ExpeditionSaveService remain the **only** durable owner of current Solo player+world state. This foundation adds metadata/validation only, no parallel save file and no auto-migration.

## PvP future rules (not implemented in this change)

- Attack on peaceful players assigns attacking-side responsibility, including players voluntarily joining that attacking team.
- Defenders (including players who already have an unrelated aggressor flag) do not acquire new responsibility by defending.
- Attacking another aggressor alone does not create this responsibility.
- Aggressor highlighted immediately; city exit locked during conflict, then 15 minutes after combat ends.
- Other map exits remain available; sanction follows the player across map instances and reconnects.
- Active assistance enters from the settlement/map entrance and traverses the real map to join the ongoing fight.

## Next integration stage

1. Audit and adapt LocationGenerator / MapRegionGenerator to biome-bound instances.
2. Replace fixed 12×12 live-map setup and three hard-coded NPC with versioned generated MapState.
3. Bind active instance metadata to current SoloGameState using a one-way, once-only migration with regression fixtures. Preserve existing combat receipts, explored cells, defeated spawn IDs, loot and character ownership.
4. Add settlement / region entry and exit gates, then travel graph and timer jobs.
5. Build UI after engine and persistence regression tests pass.

## Production generator integration checkpoint

`MapInstanceGenerationService.generate(instance, settlements)` now validates immutable MapInstance identity and invokes the **existing** `LocationGenerator.generate`, which already calls `MapRegionGenerator` and produces region definitions, NPC placements, region NPCs, objects, encounters, patrols, guards, boss groups and traversable entrances. The existing generator remains the only source of generated content; no parallel map generator was created. `tests/map/map_instance_generation_runner.gd` verifies deterministic generated content and generation-version rejection.

**Not yet implemented:** biome-specific terrain tuning (the production generator currently starts from grass and its existing thematic regions), authoritative runtime mounting of all generated NPC/patrol variants, live 12×12 replacement, settlement navigation, or Solo save migration. The adapter does not make these claims. Integrate those in subsequent tested commits without overwriting `solo_game_state_v1.json` or losing defeated-NPC receipts, ground items and combat checkpoints.
