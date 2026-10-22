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


## Actual screenshot evidence — successful Solo Visual Audit

**Run:** https://github.com/Archoniou1987/Battle-of-Artheon/actions/runs/39755177554  
**Artifact:** `solo-visual-portrait-landscape` (PNG captures, 390×844 and 844×390), successful standalone capture.

Verified screenshots `portrait_00.png`, `portrait_03.png`, `landscape_00.png`, `landscape_01.png`, and `landscape_07.png`. Images are of the real scene's Control hierarchy **with synthetic fixture values**, not actual saved battle state.

### Observed outcomes, not assumptions
- Portrait first frame contains essentially all encounter controls, HP bars, hero equipment, zones, abilities, elixir picker, End Round action, log and return-to-town button. There is extensive unused dark area beneath controls. Typography is small at 390px width.
- Portrait `_00` and `_03` look identical, reflecting no meaningful scrolling in the fixture.
- Landscape first frame shows top of one long vertical column. Second frame scrolls the same column; no responsive two-column combat layout is present.
- Hero and NPC HP bars are visible, but numerical HP appears in a compact summary above the bars rather than overlaid on each.
- No portraits, equipment art, rarity frames or red/blue target silhouettes are drawn.
- Buff/debuffs are textual chips rather than art icons on avatars.
- Empty gear symbols, large dropdown rows, and dense text make the scene visibly diagnostic rather than a final mobile RPG.

### Priority implementation order
1. Build an orientation-responsive **arena layout shell** without duplicating combat state: portrait stacked but compact, landscape split fighter/commands/log. Preserve existing round submission contracts and terminal persistence.
2. Introduce a reusable fighter widget with name, readable HP/MP and a reserved avatar art region; NPC group should support multiple cards, not only one.
3. Replace attack/defense dropdown/checkbox visuals with five-zone touch controls, retaining existing canonical hit/block submission.
4. Replace ABI and potion dropdown presentation with respectively five and four visible buttons, still allowing at most one ability and one potion per round and retaining shared potion cooldown.
5. Bind actual artwork and rarity frame resources to ten equipment slots; keep same persisted item instance IDs and active validation.
6. Adapt effect icon strips to avatar corners with overflow and accessibility on mobile taps; compact log should remain readable.
7. Re-run screenshot capture and manual ABI only after a meaningful coherent batch, to avoid paid workflow churn.

**Status:** visual audit completed; visual redesign has **not** been implemented. CI outcome of screenshot workflow is not evidence of production gameplay appearance or touch usability.
