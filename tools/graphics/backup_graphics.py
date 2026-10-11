#!/usr/bin/env python3
"""Create a local, versioned graphics backup. Run manually; no cloud upload."""
import hashlib
import json
import pathlib
import subprocess
import sys
import zipfile
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "data/graphics/atlas_registry.json"
ICONS = ROOT / "data/graphics/icon_registry.json"

def main():
    subprocess.run([sys.executable, str(ROOT / "tools/graphics/validate_registry.py")], check=True)
    entries = json.loads(REGISTRY.read_text(encoding="utf-8"))["atlases"]
    files = [REGISTRY, ICONS]
    for entry in entries:
        files.append(ROOT / entry["path"].removeprefix("res://"))
    # Outside the repository by default. User can copy this archive to Google Drive.
    target = pathlib.Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else ROOT.parent / "Battle-of-Artheon-Backups"
    target.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    archive = target / f"graphics_backup_{stamp}.zip"
    if archive.exists():
        raise FileExistsError(archive)
    hashes = {}
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED) as z:
        for path in files:
            name = path.relative_to(ROOT).as_posix()
            data = path.read_bytes()
            z.writestr(name, data)
            hashes[name] = hashlib.sha256(data).hexdigest()
        z.writestr("SHA256SUMS.json", json.dumps(hashes, indent=2) + "\n")
    with zipfile.ZipFile(archive) as z:
        for name, expected in hashes.items():
            if hashlib.sha256(z.read(name)).hexdigest() != expected:
                raise RuntimeError(f"Backup verification failed: {name}")
    print(f"Verified backup: {archive}")
    print("Copy this ZIP to your independent local/cloud backup storage.")

if __name__ == "__main__":
    main()
