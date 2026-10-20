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
| 3 | Head armour, first eligible ABI |
| 4 | Chest armour, first eligible ABI |

- Always five equal squares, a single contiguous row, no extra spacing.
- Off Hand / rings / gloves / belt do not add active ABI.
- The content layer only displays the canonical ABI assigned from the source.
- An empty position stays visible even if a slot currently has no ability.

## Validation
- `tests/ui/square_slot_interaction_runner.gd`: geometric invariants, five system ABI buttons, press overlay and empty equipment information.
- `tests/items/item_abi_chain_runner.gd`: MH/Head/Chest slot ordering, duplicate exclusion and Off Hand exclusion.
- Existing `tests/ui/arena_open_smoke.gd` and `tests/ui/elixir_abi_press_runner.gd` must also pass.
- CI on this revision has **not yet been run**. New/updated fixtures do not constitute a successful runtime test until the workflow finishes.
