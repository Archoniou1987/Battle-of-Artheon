#!/usr/bin/env bash
# Portable Godot 4.5.1 web export: works on Linux with Godot and Web export templates installed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-godot}"
OUTPUT_DIR="${OUTPUT_DIR:-build/web}"
mkdir -p "$OUTPUT_DIR"
"$GODOT_BIN" --headless --editor --path . --quit
"$GODOT_BIN" --headless --path . --export-release "Web" "$OUTPUT_DIR/index.html"
for file in index.html index.wasm index.pck; do
  test -s "$OUTPUT_DIR/$file" || { echo "Missing or empty: $OUTPUT_DIR/$file" >&2; exit 1; }
done
echo "Web export ready: $OUTPUT_DIR"
