# Live Solo hex navigation & patrol integration

## Implementation

The already-developed `DebugMapCanvas`, `DebugMiniMap`, `SafeMapNavigation`, `MapPatrolRuntime` and `LocationGenerator` are reused by the main Solo expedition. No second navigation or combat engine is introduced.

- Two taps on an explored hex: first plans the route; second begins auto-movement. The Stop button interrupts it. Route generation uses the existing safe pathfinder and terrain delay rules: road 2 seconds, plain 4, rough/forest 6, swamp 10.
- Each *completed* player step calls `SoloLiveMapSession.move_one_step`; this is the original single-GameState save boundary. A route is an in-memory UI order, not an independent save that can move the character after closing the game.
- The original `DebugMiniMap` tracks the live player and generated region footprint.
- Existing `MapPatrolRuntime` now takes the real character ID and can export/restore patrol index, direction, remaining step delay and position. Generated patrol steps commit through the SAME `ExpeditionSaveService` snapshot, and a failed write restores the previous positions.
- Patrol collision does not invoke `DebugMapViewer` mock combat. The Solo UI starts the existing canonical `SoloLiveNpcCombat` from the NPC's adjacent hex; pending combat manifests prevent further patrol movement.
- Defeated patrols are excluded from restored live patrol records and remain removed by the combat tombstone ledger.

## Boundaries not yet implemented

- Global settlement travel, linked maps and MP authority.
- Stateful patrol simulation while the application is closed; persisted last positions are resumed when opened.
- Active dynamic chase logic beyond the underlying existing patrol controller.
- Full camera framing / zoom and mobile UX refinement; CI confirms scene contracts, not visual quality.

## Regression

`generated_patrol_persistence_runner.gd` and `solo_live_route_ui_runner.gd` are included in ABI Branch Tests together with previously added map-instance and canonical GameState checks.
