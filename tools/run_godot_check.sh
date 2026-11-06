#!/usr/bin/env bash
# One local/CI contract: exit status plus diagnostic output, with isolated saves.
set -euo pipefail
mode="${1:?Supply a res:// test path, --import, or --scene}"
limit="${GODOT_TEST_TIMEOUT:-120}"
mkdir -p test-results/final-par
if [[ "$mode" == '--import' ]]; then
  name=import
  args=(--headless --editor --path . --quit)
elif [[ "$mode" == '--scene' ]]; then
  scene="${2:?Supply a scene path}"
  name="$(basename "$scene")"
  args=(--headless --path . "$scene" --quit-after 2)
else
  name="$(basename "$mode")"
  args=(--headless --path . --script "res://${mode#res://}")
fi
log="test-results/final-par/$name.log"
data_dir="$(mktemp -d)"
trap 'rm -rf "$data_dir"' EXIT
XDG_DATA_HOME="$data_dir" timeout "$limit" "${GODOT_BIN:-godot}" "${args[@]}" 2>&1 | tee "$log"
if grep -Eq 'SCRIPT ERROR|ERROR:|=FAIL|: FAIL' "$log"; then
  echo "Godot check rejected diagnostics: $name" >&2
  exit 1
fi
