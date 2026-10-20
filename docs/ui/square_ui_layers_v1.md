## Combat Integration Gate — real ABI/EFF end-to-end (2026-10-20)
### Manual CI entry point before merge
Run the existing **Combat Tests** workflow on `feature/character-inventory-ui-v1`. Its workflow file already exists in `main`, and this branch extends it with a bundled live Arena/Group integration step. The existing **ABI Branch Tests** also includes the real EFF chain. The new `Combat Integration Gate` is branch-only and may not be dispatchable from the Actions UI until its workflow definition reaches the default branch. Do **not** report a green CI run until GitHub Actions confirms it.

The lightweight manually dispatched `.github/workflows/combat-integration-gate.yml` covers seventeen real-Godot scenarios in one run. It begins with one weapon and a manual block, then exercises PAR, dual weapons, canonical ABI, active EFF, turn phases, healing, death-at-round-end, elixirs and EFF UI indicators. Every runner executes even if one fails; failing logs are uploaded.

The new `arena_real_eff_chain_runner.gd` checks three **real ArenaCombatSession rounds**, not faked EFF UI state:
1. Player equips MH `ABI003`; the actual engine casts Fireball and attaches `EFF003` Burning, which is visible as a pending debuff but must not tick in the application round.
2. An immediate Fireball cooldown retry must not consume a round, resources or events. Player legally casts chest `ABI004` Healing; engine emits the first Burning tick, applies real `EFF004` Regeneration and exposes it as a pending buff.
3. With no ABI selected, **both real periodic effects tick**. The canonical events, resource changes, read-only EFF view and Arena journal must agree.

`GroupCombatSimulator` now passes the exact same `CombatEngine` to its `CombatAttackPipeline`, sharing the seeded RNG with the duel pipeline; the group simulator regression asserts this identity. The unified read-only `CombatApi.diagnostics()` now includes a `round_trace` projection, without modifying combat state.

`CombatDiagnostics.round_trace(state,round)` is a reusable **read-only integration audit**. It exposes canonical resolved events, attack/ABI counts by actor, EFF applications, periodic ticks and event-parent lineage; it never recomputes damage and is independent of Arena UI.

Current validation status: GitHub commits created; **CI not yet executed or confirmed**. The new integration runner does not replace stochastic balance analysis, multi-participant encounters or independent numerical armour/penetration tests. Expand those only after the initial gate passes.

## Combat integration test ladder (2026-10-20)
1. **Stage 0 — baseline**: `arena_basic_round_runner.gd` and `battle_baseline_runner.gd`: one weapon, one strike, manual defence, PAR readout, rejected invalid command, canonical engine events and journal; no ABI/EFF required.
2. **Stage 1 — phase order**: `integrated_round_phases_runner.gd`: existing phase integration.
3. **Stage 2 — physical + ABI**: `arena_ability_integration_runner.gd`: two independent weapon strikes plus one canonical ABI003 in the same real round, no off-hand ABI.
4. **Stage 3 — complete vertical slice**: `full_battle_vertical_slice_runner.gd`: event trace, PAR, attack/defence, ABI, journal, and EFF *projection*. The appended EFF presentation records do not test real EFF application.
5. **Stage 4 — interaction/regression**: `arena_round_timing_interaction_runner.gd`, `round_effect_death_regression_runner.gd`, `instant_effect_surprise_runner.gd`, `elixir_mind_game_runner.gd` and existing specialized tests cover timing, EFF, end-of-round death and elixirs.

CI executes all stages in one manually started **ABI Branch Tests** run and reports each failing runner separately. A passing run is necessary but not sufficient for full combat correctness; follow up with controlled scenario matrices for mitigation, penetration, criticals, tempo, death and EFF stacking.

## Combat test ladder — first batch
- **Stage 0:** `tests/combat/arena_basic_round_runner.gd` tests a genuine Arena duel with one physical main-hand attack, one manual-block selection, a rejected invalid zone and the resulting canonical event/journal. It does not assume an exact random damage amount.
- **Stage 1:** `tests/combat/full_battle_vertical_slice_runner.gd` tests two weapons, a canonical ABI003 cast, PAR diagnostics, resource accounting, outcome and EFF read projection in the same underlying Arena session.
- **Stages 2+:** existing integrated round, end-of-round death, healing/DoT/HoT, combat RNG and broader ABI suites. Extend with systematic scenario families only after Stage 0/1 pass.
- The ABI Branch Tests workflow runs Stage 0 before Stage 1 as one batched execution. The WEB workflow verifies actual UI presentation separately.
- No isolated workflow run per minor change. A passing workflow validates the tests it contains, not every possible physical/magical effect combination.

## Combat validation sequence — stage gates
- **Gate 0 (minimal, real)**: `tests/combat/battle_baseline_runner.gd` runs one player sword attack and enemy attack, one manual block selection, PAR diagnostic readout, invalid-command atomicity, one resolved round and journal.
- **Gate 1 (integrated)**: `tests/combat/full_battle_vertical_slice_runner.gd` extends to dual wield + canonical ABI003 and engine event diagnostics; existing ABI/EFF lifecycle regressions remain in the same CI batch.
- **Gate 2+ (after baseline passes)**: scenario groups for hit/dodge/crit, shield/armour/penetration, PAR modifiers, ABI cost/cooldown, EFF timing/stack/cleanse and final-round death. Grow from deterministic fixtures; do not mutate the production battle logic for the test.
- Both new scripts are wired into `ABI Branch Tests` ahead of the deeper integrations; manual launch is required. If the first CI fails, fix only confirmed failures before expanding.
- Current Arena geometry is frozen. EFF mini-slots signal state, and the Buff/Debuff tabs own full descriptions.

## Full Combat vertical slice — stage 1
- The existing Arena is already connected to the real `ArenaCombatSession` / `CombatCommandApi` / `RoundOrchestrator` / `CombatEngine`. Do not introduce another parallel simulator for UI tests.
- EFF indicators remain compact segmented icon rows (5 cells per polarity, overflow `+N`). Detailed text belongs in the existing **Баффы** and **Дебаффы** tabs; tapping the icon jumps to its tab instead of presenting a second popup. Arena tooltip is navigation-only.
- `tests/combat/full_battle_vertical_slice_runner.gd` tests: real equipment and PAR readout, invalid command atomicity, two weapon attacks, one canonical ABI003, resource debit, resulting event trace, journal grouping and the same-session EFF view. Post-round fixture EFF records test the projection only; they are **not** a substitute for EFF lifecycle tests.
- Existing round EFF tests, end-of-round death tests, attack pipeline tests and canonical ABI runners still own deeper mechanics. Expand coverage incrementally to a scenario matrix without replacing those tests.
- Run ABI Branch Tests and Web Preview after grouped changes. The new runner is part of the ABI integration batch and has not yet been validated by CI.

## Temporary EFF icon artwork
- Arena EFF icons reuse the first cell from the **existing** `assets/items/items_atlas_01.png` (8×8 atlas) for both buffs and debuffs.
- Buff EFF frame: green `#55bf73`. Debuff EFF frame: red `#d95757`. The shared item image remains untinted.
- EFF tooltip preserves the actual effect name, duration, stacks and pending flag; overflow tiles display `+N` instead of item art. Missing atlas art falls back to the existing symbolic marker.
- This applies to real EFF rows and Visual Lab EFF scenarios, without changing effect mechanics or Arena geometry.
- Run ABI and WEB CI together after this batch, not after every minor visual tweak.

## Arena Visual Lab — ABI/EFF presentation fixtures
- In Arena open **Визуал**, use **ABI — визуальные состояния** for real slots / all five examples / selected first slot / unavailable examples. ABI examples are mouse-transparent labels/outlines placed on existing ABI button geometry; the combat ability availability, selection, IDs, costs and cast logic are unchanged.
- Use **EFF — состояния эффектов** to show actual combat effects, example buffs and debuffs, overflow (7 entries in each row, last visible tile displays `+3`), or examples with a pending effect.
- The effect examples flow through the existing `_effect_entries`, `_refresh_effect_display`, and tooltip detail display; they never write to the real combat session or effect services.
- **Сбросить оформление** reverts both ABI and EFF to live battle display.
- No geometry adjustments. CI is intentionally batched with subsequent changes rather than triggered per small commit.

## Visual Lab v0.2 — experiment workbench
- **Inventory:** visual scenario dropdown (live equipment, rarity examples, fully equipped preview); equipment-group scale (80–105%) and horizontal offset (−20…+20 logical pixels). Existing theme, ghost icons, empty borders and background opacity controls remain available.
- **Arena:** Visual Lab button exposes shared theme presets and mock equipment scenarios for player/enemy. This is presentation-only, not the existing ABI Lab or CombatSession.
- Mock examples are implemented as `VisualLabPreview` overlays on genuinely empty `ItemIcon` nodes; they never add items to the repository, change ownership, grant stats or select ABI.
- Geometry sliders affect only the **Inventory equipment group**, never bag inventory, touch targets outside that group, or saved game rules. Reset returns its scale to 0.9025 and position to (23,18).
- This remains a transient prototyping tool. A/B persistence and drag-and-drop positioning are deliberately out of scope pending mobile usability review.
- Run ABI Branch Tests first, then Web Preview and verify controls in portrait and landscape.

## Visual Lab: experiment layer (v0.1, Inventory)
- In browser preview, open **Inventory → 🎨 Визуал**. Options: Original / Bronze / Steel palettes, empty ghost illustrations on/off, empty frame on/off, and backdrop strength 15–100%.
- **Reset** returns to baseline (blue stone, frame only, full backdrop), without modifying equipment, item rarity, combat stats or saves.
- `ui/shared/visual_lab_presets.gd` is the reusable design-token registry. `VisualLabPresets.configure_empty` only touches empty cells; an occupied cell retains its rarity border.
- Runtime controls are intentionally **session-only**; not coupled to persistent character state or production settings.
- Do not treat these palette variations as finished art: they are experiments for finding workable visual directions, later extensible to Arena.
- The UI regression runner asserts the theme, frame and ghost controls plus reset.

# Square UI panels v1 — interactive foundation (2026-10-20)

## Two squares, one geometric contract
- Inventory and Arena each retain their own square (logical 480×480).
- The square always scales **uniformly**. Portrait/landscape can move the square and adjacent panels, but never rearrange the slots *inside* the square.
- `SquareUiGeometry.fit()` is now the shared sizing rule. All internal coordinates are relative to the same logical square.

## Three independent layers
1. **Square background:** decorative base, only a dark empty-slot backdrop, a modest permanent frame and faint silhouette. No item rarity, charges, cooldown, ABI ID, combat state or tooltip baked in. Final composite 1:1 background images for the two squares are **not yet installed**; existing empty slot sprites remain temporary art.
- `ItemIcon.set_empty_art_in_background(true)` is ready for the final PNG: it hides temporary empty-slot sprites and outlines but leaves the hit target and equipped item rarity frame intact. Keep the switch **off** until the image contains the precisely aligned slot art.
2. **Content and transparent hit areas:** equipped item icon (with its rarity frame), ABI icon/text, potion icon; the slot's semantic ID and hit target; empty-slot tooltip / touch description. When the proper base image is installed, empty sprites can be hidden while retaining their clickable regions.
3. **Interactive state:** one lightweight glow/outline on hover, a brief pulse on button press, a persistent outline only for a selected/committed ABI, and gameplay-controlled disabled/cooldown states. `SquareSlotFeedback` affects only visuals. It must not change `Button` dimensions or scale, emit gameplay commands, or intercept mouse/touch events.

## Frame-only composition pass (2026-10-20)
- Inventory and Arena empty equipment slots now hide all **ghost/silhouette icons** but keep a neutral 2px interactive frame and readable empty-slot description.
- Empty elixir slots also keep a neutral system frame; filled elixirs still display their own icon/charges.
- Five empty ABI buttons were already system squares; no decorative ABI atlas is baked into them.
- This is a **non-destructive display switch** (`ItemIcon.set_empty_placeholder_icon_visible(false)`). Atlas files remain in the repository for rollback and art design. Item rarity frames remain entirely tied to equipped items, not to placeholder art.
- Temporary neutral frames expose the current slot positions; **do not assume those coordinates are final** until aligned against the actual 1:1 square background and verified visually on device.
- Bag item icons are unaffected because the request concerns empty equipment/elixir/ABI slots inside square panels.

## Input behavior
- Hover (desktop): a mild brightening and slot description.
- Tap/click (mobile or desktop): tactile pulse; for empty Inventory equipment the popup displays e.g. "Шлем — пусто".
- Equipped item: its normal item detail, rarity, equip or inspect behavior stays unchanged.
- Combat ABI: click is **not** a reversible selection; actual `instant` resolves on click, `standard` commits on click, all others lock this round.
- End Turn remains a graphical button; its atlas image briefly changes tint and returns to normal after release.
- No persistent glow on inactive slots, no animation that shifts pixel coordinates or impairs tapping.

## Five immutable Arena ABI slots
| index 0–4 | item source |
| --- | --- |
| 0, 1, 2 | Main Hand weapon, abilities 1–3 |
| 3 | Chest armour, first eligible ABI |
| 4 | Head armour, first eligible ABI |

- Always five equal squares, a single contiguous row, no extra spacing.
- Off Hand / rings / gloves / belt do not add active ABI.
- The content layer only displays the canonical ABI assigned from the source.
- An empty position stays visible even if a slot currently has no ability.

## Validation
- `tests/ui/square_slot_interaction_runner.gd`: geometric invariants, five system ABI buttons, press overlay and empty equipment information.
- `tests/items/item_abi_chain_runner.gd`: MH/Chest/Head slot ordering, duplicate exclusion and Off Hand exclusion.
- Existing `tests/ui/arena_open_smoke.gd` and `tests/ui/elixir_abi_press_runner.gd` must also pass.
- CI on this revision has **not yet been run**. New/updated fixtures do not constitute a successful runtime test until the workflow finishes.
