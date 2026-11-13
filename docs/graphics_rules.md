# Graphics rules (v1 foundation)

This is a **technical test fixture**, not an item database. The 64 icons and 22 preview items are temporary examples.

## IDs and rendering
- Each atlas has a stable `atlas_id` and `version`; each icon has a stable `icon_id`.
- Item templates eventually reference `icon_id`. Never store atlas coordinates in production item templates.
- `icon_registry.json` resolves `icon_id` to an atlas/version and zero-based `cell_index`, in row-major order.
- `atlas_registry.json` resolves atlas/version to a PNG path and grid dimensions.
- Rarity frame/glow and inactive-equipment treatment are UI effects, **not painted into atlas images**.
- Keep `icon_path` for exceptional standalone artwork. `atlas_index` is a legacy preview fallback and must not be used for new content.
- Never reuse retired IDs. To change the artwork or layout, create a new version **at a new file path** and retain old versions for compatibility.

## Integrity and recovery
- Run `python3 tools/graphics/validate_registry.py` manually after adding/changing graphic resources. No CI is triggered by this command.
- The validator checks file existence, Git blob hash, unique IDs, atlas references and cell bounds. It prints SHA-256 for archiving.
- Git history is not an independent backup. Preserve **PNG + both registries + hash manifest** together in a dated ZIP archive outside the repository; copy it to a local drive and Google Drive.
- Verify that a backup ZIP opens and that extracted file hashes match before treating it as a valid backup. Never overwrite the only good backup.
- Do not delete or replace an atlas PNG without checking its references and restoring a verified archive if needed.
- Restoring: extract the matching version of the PNG and JSON files to their original paths, run the validator, then verify a Godot preview.

## Scope
No icon categorization, asset management UI, full item catalog, automatic backup service, or automatic CI/deploy is part of this stage.
