# Ground Loot Solo Foundation — 2026-10-21

## Approved Solo Final-v1 gameplay

The hex map is navigation. In portrait mode the lower panel, and in landscape
mode the right-side panel, host tabs led by **«На клетке»**. This tab reads the
contents of the PLAYER'S CURRENT cell, not an inspected distant hex. It shows
compact icons for existing items, animals, NPCs and interactive quest/world
objects. Selecting an icon reveals contextual actions:
- Item → inspect / pick up (requires five seconds)
- Hostile NPC → attack, even if AI chose not to auto-aggro
- Peaceful animal → hunt (uses the ordinary combat engine)
- Trader/quest giver → talk
- Resource/quest object → gather / activate

NPC auto-aggression is independent of the player's ability to initiate combat.
An underlevel bandit may ignore the player, but can still be attacked.
The map and combat remain separate owners of action timing.

## First code package: GroundLootService

`core/map/ground_loot_service.gd` is an **opt-in, independent foundation**,
NOT yet wired into live map UI or battle settlement:
- Stores `ground_item_instances` inside `ExpeditionState.world_state`.
  Persistence uses existing `ExpeditionState.to_dict()`; item definitions
  stay in `ItemRepository`, with the SAME `instance_id`.
- `place_unowned` places an existing instance on a cell. It does not roll
  the item or allocate a second copy. The caller must verify it is not
  still owned by another entity; do NOT call blindly on an NPC inventory.
- `items_at` lists entries for the current cell, filtered by owner.
- `drop_from_bag` moves an unequipped bag item to the current map cell
  without deleting the ItemRepository instance. A separate city inventory
  'discard' path must continue destroying the item rather than placing it.
- `begin_pickup` starts a 5-second action; `finish_pickup` rechecks the
  cell, ownership, live item, free bag slots, weight limit and elapsed time.
  `cancel_pickup` handles movement/attacks/scene interruption.
  No random failure chance is assumed. In-progress actions are ephemeral
  across process restarts and never reserve the item.
- Normal ground items have `policy=expedition` and DO NOT EXPIRE after
  15 minutes. Optional `policy=timed` supports separate world events.
- `remove_expired` only removes TIMED objects from the repository.
  Ground items using EXPEDITION are removed when the expedition really closes,
  in a FUTURE explicit cleanup transaction (not yet implemented).

### Capacities

`finish_pickup` accepts `maximum_slots` and `maximum_weight`.
Slots default to the CharacterState `bag_capacity` value if no override
is supplied; a negative value means no configured cap. Weight uses item
`weight` in `ItemRepository`; unsupported/malformed/negative weights
fail closed. Specific limits, stack rules and detailed balance are not yet
approved. Both constraints can be enabled independently.

### Existing systems left unchanged (intentional)

`EncounterLootPool` and `MapCombatSettlementService` currently use a
15-minute encounter reward TTL and a pool-specific claim API. Their proven
round checkpoints, committed reward receipts and world snapshots are NOT
replaced by this foundation. An **adapter/migration package** must move
confirmed drops to per-cell ground records exactly once, prevent simultaneous
membership of the same instance in pool + bag + ground, migrate tests and
remove the old TTL for ordinary Solo drops.

`MapWorldCommitService` snapshots ExpeditionState.world_state and the
ItemRepository/Inventory together; future scene orchestration must call
`save_progress` after successful pickup or drop, and must restore the
authoritative bundle after process restart.

### Future cell interaction architecture

One read-only `CellContent` projection should combine:
1. Ground items for player.position;
2. Alive/present NPCs from `MapNpcBridge`;
3. Non-NPC world objects / quest objects from map cell state;
4. Data-driven contextual actions from a resolver.

No new combat calculations or dedicated deer combat subsystem are required.
Hunt/attack calls the same MapEncounterCombatService used for hostile NPCs.
Full UI navigation and the generic object registry follow after grounding
the loot settlement adapter.

## Validation

New manually triggered early ABI Branch Tests step:
`tests/map/ground_loot_solo_runner.gd`.
It tests cell filtering, unique item transfer, five-second gate, no early
claim, weight and slot limits, interrupted pickup, map drop, expedition
serialization, no 15-minute expiration, timed cleanup, and replay rejection.
CI has not yet been run for this new package.
