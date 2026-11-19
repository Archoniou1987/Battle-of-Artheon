# Live hex-map screenshot regression: legacy state + viewport geometry

Observed in mobile Web Preview on 2026-10-23:
- The game displayed a plain 12x12 map with only IN visible, while the approved debug viewer displayed the 20x20 generated map with regions, NPCs, objects and patrol markers.
- The mini-map was rendered as a stretched, full-width horizontal strip rather than an inset square.

Root causes:
1. `SoloGameStateService.enter_generated_map` deliberately continued an existing legacy 12x12 world when prior battle/loot ledger keys existed, to avoid silently reinterpreting battle outcomes. This was correct for persistence but the user had no way to opt into a generated world without resetting the game.
2. `DebugMiniMap` was inserted directly into the full-width `VBoxContainer`, causing it to stretch.

Fixes:
- `SoloGameStateService.upgrade_legacy_map` provides an **explicit** transition from an active legacy expedition. A pending combat, unclaimed ground-item registry or unclaimed encounter loot pool blocks it. Same saved character, inventory, repository and combat history; original seed/position are recorded. Uses the production generator to create the 20x20 MapInstance.
- The live UI shows a visible generated-map action ONLY on a legacy map.
- The map scene now clips the canvas inside a square-height viewport and positions the original `DebugMiniMap` at its bottom right, with a fixed 155x155 size, not in the page flow.
- A production-safe-by-default developer visual toggle, `Открыть всю карту (тест)`, reveals the underlying existing map markers visually without granting movement access to undiscovered cells or changing the save state.
- ABI Branch Tests exercise the responsive mobile UI and refuse/accept legacy transition including unclaimed ground loot.

This is an explicit map replacement for the original prototype; it is not a generalized ability to create/join arbitrary multiplayer instances. Existing dynamic map and fight integration remain owned by the same GameState.
