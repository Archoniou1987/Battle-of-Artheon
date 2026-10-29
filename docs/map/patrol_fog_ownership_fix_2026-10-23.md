# Patrol fog-of-war leak fixed — 23 October 2026

Observed in mobile Web Preview: user saw rapidly expanding yellow/green explored areas on the mini-map as NPC patrols moved, even though player visibility was correctly limited to 3 hexes. Underlying cause: `TacticalMapState.move_entity()` indiscriminately set destination `discovered=true` and `visited=true` for **every** moving entity, including `MapPatrolRuntime.advance()`. When the player subsequently moved, `SoloLiveMapSession.move_one_step()` persisted all discovered cells, including those revealed by patrols.

Corrected `move_entity(entity_id,to,reveal_destination=true)` with an explicit flag: player movement retains discovery by default; `MapPatrolRuntime.advance()` opts out. Same canonical TacticalMapState and patrol runtime; no parallel fog system or UI-only concealment. The mini-map reflects discovered cells from the map state and only the player determines new persistent exploration.

Regression `tests/map/patrol_fog_ownership_runner.gd` verifies NPC traverses unknown cells without changing discovery or exploration snapshots, while player movement still discovers terrain. Wired into ABI Branch Tests.

**Legacy-save limitation:** cells already improperly persisted by older patrol movement are indistinguishable from legitimate player exploration in `world_explored_cells_v1`. Do not silently erase legitimate discovered cells. New moves no longer expose patrol routes; starting a new expedition provides a clean map for definitive before/after visual comparison. This does not change the approved 3-hex sight radius, square camera, patrol combat, group battles, or long-lived Solo combat journals.
