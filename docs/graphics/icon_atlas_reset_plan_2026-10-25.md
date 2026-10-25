# BOA — Icon Atlas Reset & Visual Integration (stage 0)

Source branch: feature/character-inventory-ui-v1
Starting commit: 0bca77837fe4e10b5621c7c8b878097a9bc5b2e9

## Approved scope
1. Remove *gameplay/catalog* item templates from active game presentation, **not** combat testing fixtures until equivalent fixtures are isolated. Do not delete PAR definitions or combat contracts.
2. Retire old item-icon atlases and registries only once no live path refers to them. Preserve backgrounds, avatar and arena UI.
3. Replace graphical End Round skin with a normal Godot Button and translatable key; retain round action signal.
4. Import previously approved BOA_ITEMS_LEVEL_1-5_ATLAS_8x8_2048_RGBA.png (64 icons), BOA_WEAPONS_ATLAS_4x4_SWORDS_AXES_1024.png (16 icons, 1 px guide grid, preview only), and BOA_RARITY_SLOT_ATLAS_GODOT_768x512.png (6 rarity backgrounds).
5. Add an isolated icon-gallery preview showing icons over every rarity background; no templates required.
6. Validate source PNG dimensions/alpha/border alignment and Godot UI rendering before populating new item templates.

## Verified current dependencies
- data/items/arena_templates.json is used by core/items/item_template_service.gd and core/items/arena_test_equipment.gd.
- data/graphics/{atlas_registry,icon_registry}.json currently describe assets/items/items_atlas_01.png.
- ui/inventory/item_icon.gd references both the item atlas and multiple slot art atlases.
- assets/ui/buttons/end_turn/BOA_END_TURN_SKINS_ATLAS_V1.png exists; button usage must be audited across scenes/scripts.
- Several test suites assert item templates and the original inventory behaviour.

## Safety
Do not hard-delete assets, test templates or references as a blanket operation. Preserve reversibility, isolate fixtures, and run Combat, ABI, SOLO and UI CI before integration.
The initial branch exists to protect the known-good working branch.
