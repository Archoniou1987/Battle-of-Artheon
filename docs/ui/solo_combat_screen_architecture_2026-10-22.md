# Battle of Artheon — Solo Combat Screen architecture (2026-10-22)

## Decision

The existing \`ArenaScreen\` and \`ArenaCombatSession\` remain a **training / balance test stand**. Their established dark-fantasy presentation is the visual reference, not the live fight controller. Do not embed the Arena owner in the map or introduce a second combat engine.

The production expedition now presents a separate \`SoloCombatScreen\` from \`ui/arena/solo_combat_screen.gd\` over the map. This is a **UI-only view + command composer**. Its two external signals are:

- \`round_requested(orders: Dictionary)\` — complete player order, including physical target zones, manual defence, chosen ABI and chosen elixir, or an empty dictionary for terminal confirmation.
- \`elixir_selected(slot: int)\` — request read-only recalculation of ABI availability in case the elixir restores mana.

The only gameplay owner remains \`SoloLiveNpcCombat\` / \`GroupCombatSimulator\`. \`scenes/main/solo_live_map.gd\` bridges \`combat_view()\` into an explicitly display-only snapshot, then calls \`live_combat.play_round(orders)\`. There is no separate resource debit, RNG, ability cast, EFF tick, checkpoint or settlement in the UI. \`ArenaCombatLog\` remains a shared read-only renderer of canonical CombatEvents.

## Visual system

- Arena-inspired dark-blue cards and warm typography, fighter avatars, HP/MP numeric overlays, AP readout, 10 real item slots via existing \`ItemIcon\`/rarity frames.
- One hero card and separate NPC cards for an arbitrary live cohort. Only the authoritative \`controls.target_id\` is marked; tapping another NPC does not fabricate retargeting.
- Five red physical-attack body buttons and five blue manual-defence body buttons using existing zone atlas. One chosen attack zone repeats for every hit; a second chosen zone splits the first and subsequent hits. Two UI-selected zones are a presentation convenience, not a cap on canonical hit count.
- Five ABI buttons (3 weapon, chest, head); one tentative ABI selection per round.
- Four elixir quickslots; selecting one can update mana-dependent ABI button availability through \`GroupCombatSimulator.player_controls(player_id, selected_elixir)\`, without consuming charges.
- Disclosed BUFF/DEBUFF mini rows overlay the lower-left avatar corner. The separate Journal tab shows the last canonical round. The enemy uses the repository’s anonymous `wanderer_01.svg` portrait as a presentation placeholder until disclosed NPC-specific portrait resources exist.
- The game has three tabs: **Поединок** (Face to Face square plus scrollable controls), **Участники** (two roster columns: Союзники / Противники), **Журнал**. Portrait places actions below the square; landscape places actions alongside it. The single main round button stays outside these tabs and is the only control that submits orders.
- Finished but uncommitted checkpoint still allows terminal confirmation, sending \`{}\` to the existing recovery/settlement path.

## Compatibility / safeguards

- Existing \`SoloLiveNpcCombat.start/resume/play_round\`, \`GroupCombatCheckpointService\`, elixir journal, manifest, atomic victory and defeat settlement, and end-round death ordering are unchanged.
- \`SoloCombatScreen\` never creates \`ArenaCombatSession\`, \`CombatEngine\` or \`CombatState\`.
- The old Solo diagnostic controls remain **temporarily mounted behind the hidden map** to preserve existing development test contracts while the first new-screen batch is validated. They are not player-visible or the source of submitted gameplay orders. Delete them and rewrite old-only tests in a subsequent cleanup batch after first green CI.
- Real character stats, item ownership, NPC status and attack targets come exclusively from the canonical snapshot and repository.
- Avoid asserting accurate final mobile visual polish before Godot screenshot inspection.

## Verification pending

No CI was started by the assistant. The manual ABI Branch Tests now includes \`tests/ui/solo_combat_screen_runner.gd\` for UI commands, multi-NPC composition, stun, terminal confirmation and both orientations. The separate manual Solo Visual Audit captures the actual \`SoloCombatScreen\` using a clearly labelled synthetic 2-NPC fixture in 390×844 and 844×390 viewports.

**Known next refinements:** full texture icons for ABI/elixirs/effects instead of transitional symbols/IDs; actual NPC-specific portraits rather than the anonymous placeholder; richer multi-enemy targeting UX if the backend adds selectable targets; smaller-screen touch dimensions and responsive screenshots; remove technical UI dead code after CI. No gameplay math should be changed to fix presentation.


## Post-CI visual audit (Oct 22, 2026)

Both original checks passed at `294e1df7efbe667592dad18761e304b530043da7`:
- [ABI Branch Tests #39761530040](https://github.com/Archoniou1987/Battle-of-Artheon/actions/runs/39761530040)
- [Solo Visual Audit #39767725662](https://github.com/Archoniou1987/Battle-of-Artheon/actions/runs/39767725662), artifact `solo-visual-portrait-landscape` ID `12420678416`.

**Actual PNGs inspected:** `portrait_00.png` (390×844), `landscape_00.png` (844×390). These are real Godot scene captures with **fixture**, not player-save gameplay. In both orientations the game surface renders, shows two NPCs and the separated fighter/actions columns; the footer action remains anchored. Main issues seen were tiny text and touch controls, substantial unused lower space, and all 10 displayed equipment cells appearing blank even though the fixture provided helmet/sword artwork.

**Confirmed root cause:** `_fighter_card()` calls `ItemIcon.set_item()` before the detached card is inserted into a live scene tree. `ItemIcon._ready()` later resets the item to empty. The UI now defers item binding until after `_ready()`, without touching ownership or equipment. The new UI test verifies the first item's retained instance ID and actual texture.

**Size adjustment:** `project.godot` retains the shared 720×720 canvas-items stretch configuration, so 48–53 logical pixel buttons shrink to roughly 26–29 physical pixels in a 390px viewport. The new screen increases font sizes and control minima (attack / defense 84×83, ABI 84×80, potion 90×79, End Round 238×82 logical) without globally changing the existing Arena/Inventory/game scene scaling. After fresh captures, visually inspect clipping and ensure the minimum physical touch targets are appropriate. No exact final art or touch usability is claimed before new CI and PNG inspection.

**Validation status:** these subsequent adjustments are committed but **not yet verified**; no CI triggered automatically. The next manual batch should run ABI Branch Tests then Solo Visual Audit on the new SHA, not independently rerun tests per small UI edit.

## Face to Face correction (2026-10-22)

The user rejected the interim vertical list of fighter cards as the wrong **primary** battle visual. Its good ABI/Solo checks only meant the implementation rendered and commands remained healthy, not that the UX met the visual target. The UI was therefore reorganized: a **single 1:1 Face to Face square** uses two 232px fighter positions modelled after training Arena, and all extra combatants are in a **separate two-column participant tab**, not appended into the live duel view. The Ally column currently includes the solo player only, since `SoloLiveNpcCombat.combat_view()` currently exposes just the player and opponents; it may render additional allies in future only if an authoritative snapshot supplies them. Enemy list is fully read-only and cannot retarget combat through list taps.

The same synthetic-fixture Solo Visual Audit now captures both the duel square and the participants tab in portrait and landscape. ABI test checks the single-two-fighter invariant even with two NPCs, and rosters stay separate. This correction is not CI-verified as of this note.


## Universal Arena UI migration (2026-10-22)

**Supersedes the earlier separate visual design:** The Arena square is the canonical, shared player-facing combat interface across training, expedition, solo and group battles. The map overlay is a host / data adapter only. Its secondary tabs are located **outside** the square (portrait: below; landscape: right). Never create a second fighter/command square for new modes.

Implemented in `ArenaScreen` with `external_combat_mode`:
- In an expedition, no `ArenaCombatSession` is constructed and no test round handler is connected. Only the expedition's `SoloLiveNpcCombat` can resolve actions.
- Existing Arena UI displays live fighter snapshots, zones, equipment slots, ABI and elixir buttons. Signals bridge chosen zones, ABI, potions and End Round into `SoloCombatScreen`'s canonical `round_requested(orders)` output.
- The map still owns checkpoints, combat outcome, inventory transactions and settlement.
- The Arena test screen remains available in its original mode for diagnostic work.

**Mandatory cleanup rule:** Trial Solo Face-to-Face fighter panels, pseudo-ABI strips, placeholder status text and duplicated action control builders have been **deleted** after mounting the shared Arena square. Do not restore them. The Solo wrapper retains only the secondary participants/journal tabs, an internal order adapter and temporary compatibility plumbing needed by the map. Further obsolete compatibility plumbing may be deleted after passing CI and checking the actual expedition screenshots.

**Verification not yet complete:** This migration was committed without starting GitHub Actions. Run ABI Branch Tests and Solo Visual Audit manually at the latest HEAD; a green result is required before calling the integration complete. Separately inspect the real 480px Arena textures and clicks, rather than interpreting synthetic screenshots as a production-ready playable flow.


## Single-scale Arena geometry correction (2026-10-22)

The live map previously scaled `SoloCombatScreen.square_content` and also called `SquareUiGeometry.fit` within the embedded `ArenaScreen`, so the same 480px composition had independent layout calculations. **Contract now:** shared `ArenaScreen` stays at native 480×480, with internal scale exactly 1.0; the outer Solo host is the sole responsive scaler. The host computes the square edge using the **actual BattleLayout size**, after reserving the external info tabs and their separation in portrait/landscape. No Arena element is repositioned, no alternate combat square is introduced.

Regression tests assert native internal scaling, exactly one Arena child in the visual host, outer-only scaling, and that the landscape square fits within the available layout. CI and visual screenshots are still required to validate this batch; do not infer success from committed code.


## Full-height Arena / fluid information panel (2026-10-22)

Reference: approved original Arena browser screenshots in phone portrait and landscape. Do not change the phone's real aspect ratio, impose an artificial 18:9 viewport, or scale any Arena child independently.

The expedition host now puts the combat title and round label **inside the secondary information column**, not above the entire battle row. Therefore the Arena square can use the full layout height in landscape. Information tabs take the width that remains after the square, with a responsive minimum rather than the former fixed 330px reservation. Portrait places the same information column beneath the square. The original 480×480 composition and single host scaler are unchanged.

The UI regression runner now requires the external column hierarchy and a near-full-height landscape square. This is a code change awaiting manual ABI / Solo Visual CI and actual screenshot review; no claim of visual verification yet.


## Remove mistaken 480-pixel display cap (2026-10-22)

Root cause verified against `project.godot`: `window/size/viewport_height=720` and `window/stretch/mode="canvas_items"`. The map host incorrectly used `minf(SQUARE_EDGE, available_width, available_height)` (nested two-argument form), capping the *display edge* at 480 logical pixels. On a 390px-tall landscape mobile test viewport this yields approximately 480 / 720 × 390 = **260 actual screen pixels**, unlike the full-height training Arena in the reference screenshots. `SQUARE_EDGE=480` is a **design coordinate system**, not a permitted upper limit.

Now compute the host display edge as `floorf(maxf(1.0, minf(available_width, available_height)))`, preserving the existing responsive information-column allocation and one-only outer scale. The inner Arena remains native 480×480 with no secondary scaling. The regression runner checks the exact width/height bound and explicitly verifies edges >480 when space allows. **No CI has run on this change yet.**


## Container/background/ABI stability (2026-10-22)

- Fix for landscape cut-off: responsive edge is computed from `SoloCombatScreen.size` (the screen's available canvas area), rather than `BattleLayout.size`, which can be inflated by the previous frame's `square_host.custom_minimum_size` and thus feed its own oversize back into the calculation. Refit only when the desired edge changes, avoiding a feedback loop from `resized` signals.
- Keep the original Arena background texture at position (0,0) in its **native 480×480** `square_content`. Scale background, avatar and HUD together exactly once through the outer host. Do not stretch the background independently to fill the screen or the information column. Runtime visual audit prints the source texture dimensions to detect a non-square bitmap; its actual source aspect ratio is not assumed here.
- ABI button names must not alter the 5-slot strip width: each button is placed inside an exactly 34×34 cell, and button text is clipped with an 8px font. Long ability names belong in tooltips, not in layout calculations.
- Automated UI/visual checks now assert all ABI widths, original background geometry, and that the final Arena square rect lies inside the full screen in portrait and landscape (including the bottom End Turn artwork).

Status: **committed, not yet run on Godot CI**. Do not claim visual completion until ABI Branch Tests and Solo Visual Audit on the latest SHA pass, followed by screenshot inspection.


## APPROVED / FROZEN: responsive battle UI geometry (2026-10-22)

**Decision:** The project owner reviewed both final Solo Visual Audit screenshots (Portrait and Landscape) and explicitly approved the overall structure. This section supersedes earlier provisional `awaiting CI`/geometry notes above.

**Verified baseline**
- SHA `51081718384fd66d10077e40870411c9edc2d9c9`
- ABI Branch Tests: run `39805762893` — success.
- Solo Visual Audit: run `39813363741` — success; screenshots inspected and structure approved by owner.

**Layout contract — do not redesign during feature integration**
1. Reuse the original `ArenaScreen` inside the map combat overlay. Its **480×480 design coordinates and inner arrangement remain unchanged**.
2. Apply **one responsive outer scale** to the Arena square; it must fit fully inside the visible screen, including the bottom round button.
3. **Landscape:** the square is on the left and makes effective use of available height; secondary tabs are in the remaining space on the right.
4. **Portrait:** the square is above the secondary information section.
5. The Arena background covers its own square, not the entire device viewport or the separate information column. Five ABI slots have equal fixed cells; text length must not change their width.
6. Preserve both screenshot/geometry regressions and ABI checks; avoid unrelated changes to scale, root sizing, anchors, orientation, or the approved square during combat-engine work.

**Deliberately open for point changes:** the **presentation of participants** in the auxiliary roster (allies/enemies). The owner intends to display participants differently. This is *not* authorization to rebuild the square, move the information section, or change the overall screen structure. Adjust only roster content/components when the new participant design is specified.

**Next functional milestone:** validate attack zone selection, block zone selection, ABI, elixirs, and End Turn -> authoritative live Combat Engine, retaining one Arena UI and one gameplay engine.


## Functional command integration — batch 1 (2026-10-22)

The approved UI geometry remains **frozen and untouched**. Live expedition wiring already used the authoritative `SoloLiveNpcCombat.play_round()` in `scenes/main/solo_live_map.gd`, receiving commands via `SoloCombatScreen.round_requested` and returning a new canonical snapshot through `_refresh_combat_controls()`. This batch strengthens the input contract and its UI coverage; it does **not** add a second engine or change round resolution.

- Five attack zones: the Arena's selected zone list feeds the submitted hit targets; a single zone repeats as needed for dual attacks; two selected zones are kept distinct. Zero available attacks no longer fabricate a chest attack in presentation.
- Manual defense: actual block capacity from the simulator can be **zero**. Original Arena previously clamped it to one and displayed a phantom chest block. Zero now clears all blocks and disables defense selectors; stun likewise disables both zone selector groups.
- ABI and elixir: one optional selected ability ID and one optional potion slot coexist with attack/block choices. Their toggle appearances and disabled states now reflect the actual submitted selection and predicted availability. Potions may refresh ABI affordability through the existing simulator projection without spending resources.
- End Round emits the command once, disables immediate duplicate submission, and leaves authoritative verification, checkpoint commit, finalization and next-snapshot publication with the existing live engine.
- `tests/ui/solo_combat_screen_runner.gd` checks original-command output, selected button visibility, duplicate submission lock, zero-block behavior, and stun behavior.

**Verification pending:** run ABI Branch Tests for the latest SHA before marking this batch stable. Solo Visual Audit is useful if these control-state changes affect rendered screenshots; no geometry changes were made.
