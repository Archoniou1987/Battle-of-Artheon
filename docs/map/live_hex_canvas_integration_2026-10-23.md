# Playable Solo hex map integration checkpoint

The approved map foundation is the existing `scenes/debug/debug_map_canvas.gd` + `debug_map_viewer.gd` stack (odd-row hex geometry, fog, routes, regions, NPC badges, patrols, loot, minimap). It is **not** the square-button 12x12 prototype.

## Integrated now

- `scenes/main/solo_live_map.gd` renders the actual `SoloLiveMapSession.map` through the existing `DebugMapCanvas` renderer, rather than creating square grid buttons.
- Hex clicks call the existing `_move` method; this continues to use real `SoloLiveMapSession.move_one_step`, `SoloLiveNpcCombat`, real loot pickup and the unchanged authoritative `SoloGameStateService`.
- NPCs from the live `MapNpcBridge` receive the same canvas markers as the debug map. No debug fight, synthetic character, or new save owner is added.
- Mobile-layout smoke test now explicitly checks for the canonical hex canvas.

## Next integration — not yet complete

The live Solo map still mounts the existing 12×12 tactical map with three fixed NPCs. The debug viewer's **full** `LocationGenerator` output, patrol runtime, region-aware map state, terrain costs, viewport, minimap, route timers and persistent fog must be connected next as the normal generated `MapInstance` workflow.

This must be done as a **versioned migration** (keeping existing position, defeated NPC records, combat manifests and ground loot). Never regenerate over a live save just because a map scene was opened. The debugging scene may continue to be a test harness, but the underlying canonical generator and canvas are shared production components.
