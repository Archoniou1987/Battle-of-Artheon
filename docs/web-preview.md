# Battle of Artheon — Godot Web Preview and Vercel publishing

The canonical browser preview is hosted at
[https://battle-of-artheon.vercel.app](https://battle-of-artheon.vercel.app).
The Vercel project is `battle-of-artheon` (team `dryun87-9174`).

## Publish a tested branch (manual, batched)

1. Finish a group of changes on `feature/character-inventory-ui-v1`.
2. Run the appropriate Godot CI workflow(s), e.g. `ABI Branch Tests`.
   **These tests do not update the browser deployment.**
3. In GitHub Actions, open `Web Preview (Godot)`, choose
   `feature/character-inventory-ui-v1`, and tick
   **Publish browser build to Vercel** (`publish_to_vercel = true`).
   The publishing checkbox defaults to **false** to avoid accidental
   GitHub Actions/Vercel build costs on every small commit.
4. The Web Preview workflow imports the Godot 4.5.1 project, runs the
   smoke tests (including the Arena and ABI Lab dialog smoke tests),
   creates the actual Web export and publishes **build/web** to Vercel.
5. Check that the workflow's final `Publish Web build to Vercel` step
   completed successfully, not merely the Godot/ABI test steps.
6. Reopen the game at `battle-of-artheon.vercel.app` and confirm the
   new feature. On mobile browsers, reload the site if an old Web export
   remains visible in the current tab.

A GitHub commit by itself does **not** publish the Godot build. Vercel
does not compile Godot source directly for this project: the manual
GitHub workflow handles the Web export and uploading.

## Portable / backup build

Requires Godot **4.5.1** and matching Web export templates.
From the repository root run `bash scripts/build_web.sh`.
Alternatively:
`GODOT_BIN=/path/to/godot OUTPUT_DIR=build/web bash scripts/build_web.sh`.
The script imports assets, exports the `Web` preset and verifies
`index.html`, `index.wasm` and `index.pck`.
Upload **the contents of** `build/web/` to a static hosting provider,
not the Godot source tree.

## Verification

A green Godot headless test is not a substitute for browser testing.
After publication, open the game in Android Chrome (portrait and
landscape), try numeric inputs, verify ABI Lab's tabs and fixed action
buttons, and examine browser loading errors if assets fail to load.
