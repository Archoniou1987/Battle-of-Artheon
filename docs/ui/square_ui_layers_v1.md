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
