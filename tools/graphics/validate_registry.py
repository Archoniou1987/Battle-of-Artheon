#!/usr/bin/env python3
"""Read-only validation of registered immutable graphics assets. Run manually."""
import hashlib
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "graphics"

def fail(message):
    raise ValueError(message)

def main():
    atlases = json.loads((DATA / "atlas_registry.json").read_text(encoding="utf-8"))["atlases"]
    icons = json.loads((DATA / "icon_registry.json").read_text(encoding="utf-8"))["icons"]
    atlas_by_key = {}
    paths = set()
    for atlas in atlases:
        key = (atlas["atlas_id"], atlas["version"])
        if key in atlas_by_key:
            fail(f"Duplicate atlas: {key}")
        atlas_by_key[key] = atlas
        path = atlas["path"]
        if not path.startswith("res://"):
            fail(f"Invalid resource path: {path}")
        relative = path.removeprefix("res://")
        asset = (ROOT / relative).resolve()
        if not asset.is_relative_to(ROOT.resolve()) or not asset.is_file():
            fail(f"Missing or unsafe atlas path: {path}")
        if path in paths:
            fail(f"Reused atlas path: {path}")
        paths.add(path)
        content = asset.read_bytes()
        blob_sha1 = hashlib.sha1(b"blob " + str(len(content)).encode() + b"\0" + content).hexdigest()
        if blob_sha1 != atlas["git_blob_sha1"]:
            fail(f"Atlas was changed: {key}; expected {atlas['git_blob_sha1']}, got {blob_sha1}")
        if atlas["columns"] < 1 or atlas["rows"] < 1 or atlas["cell_count"] != atlas["columns"] * atlas["rows"]:
            fail(f"Invalid atlas dimensions: {key}")
        if atlas["status"] not in ("active", "deprecated"):
            fail(f"Invalid atlas status: {key}")
        print(f"OK {key}: Git blob SHA-1 verified; SHA-256={hashlib.sha256(content).hexdigest()}")
    seen = set()
    for icon in icons:
        icon_id = icon["icon_id"]
        if icon_id in seen:
            fail(f"Duplicate icon ID: {icon_id}")
        seen.add(icon_id)
        key = (icon["atlas_id"], icon["atlas_version"])
        if key not in atlas_by_key:
            fail(f"Unknown atlas for {icon_id}: {key}")
        if not 0 <= icon["cell_index"] < atlas_by_key[key]["cell_count"]:
            fail(f"Out-of-range atlas cell for {icon_id}")
        if icon["status"] not in ("active", "deprecated"):
            fail(f"Invalid icon status: {icon_id}")
    print(f"PASS: {len(atlases)} atlas(es), {len(icons)} stable icon IDs")

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        sys.exit(1)
