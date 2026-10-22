# Solo Live Map — visual audit preparation (22 October 2026)

## Scope and evidence

Reviewed current `scenes/main/solo_live_map.gd`, `solo_live_map.tscn`, `project.godot` and recent successful ABI tests through #323. Source inspection is **not a pixel-level screenshot** and does not establish that the final arena looks good. Godot executable is not available in the review environment. A separate manually dispatched Actions workflow, `Solo Visual Audit`, now exists to generate **actual Godot-rendered** portrait 390×844 and landscape 844×390 PNGs of this real scene with clearly labelled demonstration combat snapshots. No source gameplay is mutated, and this does not trigger ABI tests.

## Confirmed source-level visual discrepancies

1. **No separate arena screen composition.** The combat panel is a long `VBoxContainer` inside the map's main vertical `ScrollContainer`. All controls and log are stacked top-to-bottom; landscape shares identical hierarchy.
2. **No avatars.** The current prototype has actor labels/HP bars but does not render character portraits or equipment flanking avatars.
3. **Equipment visualization is diagnostic only.** Ten cells appear as disabled text buttons in a 5×2 grid, not item sprites or rarity frames.
4. **ABI / elixirs are dropdowns.** Five equipped ABI and four potion quickslots are modelled and available, but one `OptionButton` per group is used instead of touch icons.
5. **Attack uses dropdowns, defense uses checkboxes.** These are not the agreed red/blue five-zone silhouette selectors.
6. **Effect indicators use text chips.** Maximum eight plus overflow and canonical BUFF/DEBUFF are present, but not sprite icons over the avatar.
7. **HP values are in a text summary and hover tooltip.** The ProgressBar itself hides numeric percentage and does not overlay numeric HP; touch users cannot reliably access hover-only tooltip detail.
8. **Long text and horizontal overflow.** Starter map has a horizontal scroller; combat root scrolls vertically. Landscape especially requires examination for excessive vertical traversal.
9. **Viewport base is 720×720** in `project.godot`; actual screenshots at portrait/landscape resolutions are essential before claiming responsive UI behavior.

## Screenshot procedure

1. Open GitHub Actions → **Solo Visual Audit**, select branch `feature/character-inventory-ui-v1`, choose **Run workflow**. This is an explicitly manual, standalone workflow; unlike the general ABI suite, it captures only visual UI.
2. Open completed workflow's **Artifacts** → `solo-visual-portrait-landscape`.
3. Inspect `portrait_00.png`, `landscape_00.png` and succeeding numbered scroll segments. Labels explicitly state a fixture was used; no genuine player character, save or live combat should be inferred.
4. Record clipping, scroll depth, touch-target spacing and grouping against the approved concept: fighter avatars/HP/equipment, separate attack-defense zones, five visible ABI icons, four visible elixir icons, and prominent End Round.

## Next implementation, not yet approved by visual evidence

After reviewing actual captures, create a coherent layout with reusable fighter panels, equipment near avatar, visible zones and button rows. Keep all data bound to `combat_view()`, `CharacterState` and existing combat commands. Avoid gameplay changes and avoid claiming pixel-perfect layout before visual screenshots.

## CI status

ABI #323 succeeded on `1b66640fea6ab498be87c49fce4826db6c507716`; this audit and screenshot workflow have **not yet** been run or verified.
