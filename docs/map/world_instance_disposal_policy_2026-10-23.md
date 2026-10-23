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
- At least one effective occupant: ACTIVE. A disconnected player in an **unresolved battle** is still an effective occupant; a player disconnected outside combat is not. The server deduplicates connected players from disconnected battle participants.
- The last effective occupant leaves (including the resolution of the last unresolved battle): IDLE starts.
- Someone returns before a continuous 60-minute empty interval ends: ACTIVE, reset idle timer. A player who reconnects during an unresolved fight rejoins the same progressing fight; battle timers never freeze on disconnect.
- No effective occupants for 60 continuous minutes: CLOSED and eligible for destruction, with **no intermediate archive**.
- Pending combat/loot transactions must be resolved before the server actually destroys authoritative state.
- Map IDs are never recycled; retired world contents are not retained. A non-combat player who reconnects after their instance was closed is routed to settlement without HP or equipment penalty in v1, regardless of whether they were offline for 3 hours or longer.
- MP occupancy counts, authoritative storage, and cleanup jobs still require server implementation.

## Storage boundary
`SoloGameStateService.start_new_expedition` replaces world-local state in the sole canonical game save and reclaims dropped/pooled item instances for the old map; no extra world archive is retained. Combat recovery journals/receipts outside that GameState are a separate retention system; this change does not prematurely delete crash-recovery artifacts.

## Reconnect example and accepted v1 trade-off

Disconnect while exploring outside combat at 12:00: player no longer occupies the map. With no other players or unresolved battles, the one-hour idle timer starts. Map closes at/after 13:00. If the player reconnects at 15:00, the server routes them to the settlement and does **not** regenerate the retired map. This allows deliberate logout as a shortcut back to town; accepted for v1. A future penalty such as death/equipment wear is explicitly **not active** and needs a separate design approval.

Disconnect during MP combat: character remains an authoritative participant, occupies the instance and continues to receive one-minute round resolutions for fights with 2+ players. If the battle ends in defeat, settlement return at 0 HP is committed; only then can that participant stop occupying the map. The server never closes the instance with an unresolved fight, even if the client has been offline for over an hour. PvP/network execution remains future work; the pure lifecycle contract and tests do **not** imply live MP support.
