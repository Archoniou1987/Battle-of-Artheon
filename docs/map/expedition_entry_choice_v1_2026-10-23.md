# Settlement expedition entry choice (v1)

When the player selects the Map service from the settlement, the city UI opens a real two-button popup:

1. **Вернуться на прежнюю карту**: uses `SoloGameStateService.enter_generated_map` to continue the currently active map with its existing instance ID, seed, NPC tombstones, loot and explored cells. Old 12x12 saves remain legacy until explicit upgrade.
2. **Начать новую экспедицию**: uses `SoloGameStateService.start_new_expedition` to create a fresh 20x20 generated MapInstance. Preserves the character and ItemRepository. Before publishing the new world, the existing map world_state, seed and player position are archived under `world_expedition_archives_v1` in the SAME canonical GameState. The new map's world-local loot, combat markers, NPC tombstones, exploration and patrol state start separate, preventing stale defeat identities from being carried across maps.

Both operations refuse a pending combat manifest, and require the character to be in town. New map IDs use a monotonically increasing serial stored in GameState. Both options use the existing atomic `ExpeditionSaveService.save` boundary; no new player file is created. The popup is not shown during an interrupted battle's map resume.

**Current limitation:** archived maps are preserved as world state but are not yet selectable from a separate expedition history UI. The 'previous map' choice continues the last active instance when entering from the settlement. Returning to an older archived instance requires a future dedicated selection/recovery workflow.

## Archive retention (1 hour)

Old map-world snapshots now carry `expires_at_unix`, set to their archive time + 3600 seconds. Expired snapshots are pruned on the next canonical town save or new-map creation; no background timer, cloud job, or unbounded in-memory archive is required. The permanent map ID serial remains monotonic and is not recycled. Unclaimed item instances referenced **only** by deleted archive-world loot registries/pools are reclaimed from ItemRepository; player-owned inventory and loot still referenced by any retained map are preserved. Active map state, the player's stats and equipment are never pruned. Immutable combat receipt/checkpoint artifacts outside the GameState are not deleted by this v1 archive cleanup and need a separate safe journal-retention policy. Legacy archive records without expiration metadata expire at the first pruning pass.

## Confirmed Solo vs provisional MP lifecycle (23 October 2026)

**Solo:** The currently selected map instance remains **ACTIVE indefinitely** while the player can return to it from the settlement, even when the player is offline or staying in town. Its one-hour archive clock **does not run** while it is active. Only choosing **Start new expedition** archives the previous active map, records `archived_at_unix` and `expires_at_unix`, and switches to a new active map. Expired archive snapshots are removed during the next durable save/expedition creation. Previous-map archive recovery during that one-hour grace window is **not implemented yet**; merely storing an archive is not equivalent to allowing the player to re-enter it. The current Continue button still resumes only the latest active map.

**MP — future proposed policy, not live networking:** An online participant count above zero keeps the shared server-authoritative map active. When the last participant leaves, it enters IDLE and a 60-minute empty timer starts. Any return **during IDLE** resets the timer and restores ACTIVE. If continuously empty for 60 minutes it becomes ARCHIVED for another 60 minutes, then CLOSED and eligible for cleanup. Whether an archived instance can be restored by rejoining, and how to account for pending fights, loot claims or reconnects, must be resolved before implementing server runtime. `WorldInstanceLifecyclePolicy` models these decisions without starting any server job. ID and seed remain separate from lifecycle and retired IDs are never reused.

This provisional MP idle duration is **not** applied to Solo maps. Do not accidentally archive Solo based on zero online occupants.
