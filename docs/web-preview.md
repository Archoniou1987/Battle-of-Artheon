# Browser preview and build recovery

## Primary: GitHub Actions
Run `Web Preview (Godot)` manually on `feature/equipment-instance-chain`.
GitHub Pages is **not enabled** for this private repository, so this workflow's Pages deploy step cannot publish as-is.

## Portable / backup build (no GitHub Actions)
Requires Godot **4.5.1** plus matching **Web export templates** installed on any Linux computer/runner.
From repository root: `bash scripts/build_web.sh`.
Or: `GODOT_BIN=/path/to/godot OUTPUT_DIR=build/web bash scripts/build_web.sh`.
The script imports assets, exports the Web preset and verifies `index.html`, `index.wasm`, `index.pck`.
Upload **the contents of** `build/web/` to a static host such as Vercel; do not upload Godot source as the web root.
No GitHub Actions minutes are consumed by this route.

## Hosting caveat
Vercel project `battle-of-artheon` exists, but has no deployment yet. Vercel does not natively build Godot projects. A compiled Web export must be provided to it. Do not point Vercel at raw Godot source and expect a working game.

## Verification
A passing Godot headless smoke test is not a substitute for browser testing. After publication, open the game on Android Chrome in landscape and test hotspots, footer, panorama dragging, and loading errors.
