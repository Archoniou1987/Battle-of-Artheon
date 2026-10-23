# Settlement expedition entry choice (v1)

When the player selects the Map service from the settlement, the city UI opens a real two-button popup:

1. **Вернуться на прежнюю карту**: uses `SoloGameStateService.enter_generated_map` to continue the currently active map with its existing instance ID, seed, NPC tombstones, loot and explored cells. Old 12x12 saves remain legacy until explicit upgrade.
2. **Начать новую экспедицию**: uses `SoloGameStateService.start_new_expedition` to create a fresh 20x20 generated MapInstance. Preserves the character and ItemRepository. Before publishing the new world, the existing map world_state, seed and player position are archived under `world_expedition_archives_v1` in the SAME canonical GameState. The new map's world-local loot, combat markers, NPC tombstones, exploration and patrol state start separate, preventing stale defeat identities from being carried across maps.

Both operations refuse a pending combat manifest, and require the character to be in town. New map IDs use a monotonically increasing serial stored in GameState. Both options use the existing atomic `ExpeditionSaveService.save` boundary; no new player file is created. The popup is not shown during an interrupted battle's map resume.

**Current limitation:** archived maps are preserved as world state but are not yet selectable from a separate expedition history UI. The 'previous map' choice continues the last active instance when entering from the settlement. Returning to an older archived instance requires a future dedicated selection/recovery workflow.
