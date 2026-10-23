# Live Solo map visual and combat journal fixes — 2026-10-23

Verified user screenshots: generated 20x20 map now plays real combat; three battles completed, but combat UI displayed only last round, and map screen differed from the previously approved debug viewer composition.

## Implemented
1. **Whole-combat log**. `SoloLiveNpcCombat.combat_view` now projects all completed rounds from the actual persisted simulator `event_log` (plus elixir use details) as `battle_log`. `SoloCombatScreen` uses this for the Journal tab and retains the old `last_round_log` fallback for diagnostic tests. No competing log is saved; the checkpoint contains the canonical events, allowing recovery after restarting an unfinished Solo battle.
2. **Square-first map**. The clipped map viewport is the first visible Solo scene element, with details/actions below it, and the same 155x155 bottom-right minimap overlay used in the approved debug design. Non-gameplay introductory copy is hidden in live map. The map camera recenters on the player's actual saved hex after mount and movement.
3. **Fog safety**. The debug `Открыть всю карту (тест)` switch reveals the map visually only. Neither enabling it nor walking while it is enabled adds cells outside actual effective visibility radius 3 to explored state.
4. UI regression tests verify multi-round Journal display, square map ordering, and diagnostic fog protection.

## Still separate
The approved debug viewer has additional menus, selection states and cell-content tabs not yet wired to the live production scene. Do not add dead decorative buttons or a duplicate world/engine merely to imitate the screenshot. Establish exact gameplay navigation and cell-content integration as the next pass.

An exit/entry tile rule for new maps is not implemented in this visual/UI patch. The current validated Solo save continues to resume at its saved hex, which the user explicitly accepted for now.

## Square-only visual contract, focused revision

Following the user's clarification, prioritize the **playable square** over all lower navigation, inventory and diagnostic panels. Match the approved debug viewer's `HEX_SIZE=40.0` (earlier live map had 28.0, rendering roughly 40% more map across the same display), constrain the map viewport to an actual 1:1 square at the current layout width, keep the mini-map 155x155 inside its bottom-right corner and hide visible scrollbars while preserving map panning. The viewport/camera does not alter the fixed default gameplay vision radius of three hexes; cells already explored by legitimate movement remain dimmed while unvisited cells remain unknown.

This is a presentation contract, not a change to generation dimensions (still 20x20), movement timers, combat engine or player save. Next run ABI and Web Preview to verify actual mobile rendering.
