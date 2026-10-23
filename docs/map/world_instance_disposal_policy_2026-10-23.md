# Battle of Artheon — disposable MapInstance rule (confirmed 2026-10-23)

Map instances are **consumable**. Closed maps are not archived. Do not store terrain, NPC state, patrol snapshots, explored cells or unclaimed world loot after closure.

## SOLO
- The current map stays ACTIVE while the player explores it or returns to the settlement. Time away from the map does not retire it.
- Selecting **Return to previous map** re-enters the currently active map, keeping its seed, ID and durable world state.
- Selecting **Start new expedition** closes the former map **immediately** and irreversibly: discard its map-specific NPC state, regions, fog, loot and patrol progress, create a new seed and MapInstance, and persist the new active map atomically.
- Carry over the **same character and inventory/repository owner**. Remove only unclaimed, unowned item instances referenced by the retired map's ground and encounter-loot pools.
- Previously saved archives from the temporary design are discarded when a new map is created; the monotonic serial survives. No previous-map restoration UI or TTL is needed.
- A pending combat recovery manifest prevents closure. Character data, equipped items, confirmed awards and the active map must not be deleted.

## MULTIPLAYER (policy contract only, not server implementation)
- At least one online player: ACTIVE.
- The last player leaves: IDLE starts.
- Someone returns before a continuous 60-minute empty interval ends: ACTIVE, reset idle timer.
- No players for 60 minutes: CLOSED and eligible for destruction, with **no intermediate archive**.
- Pending combat/loot transactions must be resolved before the server actually destroys authoritative state.
- Map IDs are never recycled; retired world contents are not retained.
- MP occupancy counts, authoritative storage, and cleanup jobs still require server implementation.

## Storage boundary
`SoloGameStateService.start_new_expedition` replaces world-local state in the sole canonical game save and reclaims dropped/pooled item instances for the old map; no extra world archive is retained. Combat recovery journals/receipts outside that GameState are a separate retention system; this change does not prematurely delete crash-recovery artifacts.
