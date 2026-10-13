#!/usr/bin/env python3
"""Import .dockdoorpack files into Docks/<pack-id>/.

    import_dockdoorpack.py <file.dockdoorpack>... [--replace]

Reads each pack (inline base64 asset data), writes Docks/<id>/pack.json plus one
image file per asset, and validates the result with the shared rules in
dock_rules.py. An existing folder is left alone unless --replace is given. Any
failure prints a clear message and the exit status is nonzero; packs that
passed are still imported.

For originals.* ids, `author.isOfficial` is cleared on import: officialness
comes from the id prefix alone and the rules reject the flag everywhere.
"""
import argparse
import base64
import binascii
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path

from dock_rules import (
    ASSET_KEY, ASSET_TYPES, DockRuleError, ID_PATTERN, PACK_FILE, asset_path, heic_size, is_official_id, jpeg_size, validate,
)

ROOT = Path(__file__).resolve().parent.parent
DOCKS_DIR = ROOT / "Docks"


def stage(source: Path, staging: Path) -> str:
    """Writes the dock folder for `source` under `staging` and returns the pack id."""
    try:
        pack = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise DockRuleError([f"cannot read pack: {error}"])
    if not isinstance(pack, dict):
        raise DockRuleError(["pack must be a JSON object"])
    pack_id = pack.get("id")
    if not isinstance(pack_id, str) or not ID_PATTERN.match(pack_id):
        raise DockRuleError(["'id' must be originals.<slug> or community.<slug> (lowercase letters, digits, hyphens)"])

    if is_official_id(pack_id) and isinstance(pack.get("author"), dict):
        pack["author"]["isOfficial"] = False

    folder = staging / pack_id
    folder.mkdir()
    assets = pack.get("assets", {})
    if not isinstance(assets, dict):
        raise DockRuleError(["'assets' must be an object"])
    for key, asset in assets.items():
        if not ASSET_KEY.match(key):
            raise DockRuleError([f"asset key '{key}' must be 1 to 32 letters, digits, hyphens or underscores"])
        if not isinstance(asset, dict) or asset.get("type") not in ASSET_TYPES:
            raise DockRuleError([f"asset '{key}' type must be one of: {', '.join(sorted(ASSET_TYPES))}"])
        encoded = asset.get("data")
        if not isinstance(encoded, str):
            raise DockRuleError([f"asset '{key}' has no inline base64 'data'"])
        try:
            data = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError):
            raise DockRuleError([f"asset '{key}' data is not valid base64"])
        asset.pop("data")
        asset.pop("url", None)
        asset.setdefault("bytes", len(data))
        asset.setdefault("sha256", hashlib.sha256(data).hexdigest())
        size = jpeg_size(data) if asset["type"] == "public.jpeg" else heic_size(data)
        if size:
            asset.setdefault("width", size[0])
            asset.setdefault("height", size[1])
        asset_path(folder, key, asset).write_bytes(data)

    (folder / PACK_FILE).write_text(json.dumps(pack, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    validate(folder)
    return pack_id


def main() -> int:
    parser = argparse.ArgumentParser(description="Import .dockdoorpack files into Docks/.")
    parser.add_argument("packs", nargs="+", type=Path, help=".dockdoorpack files to import")
    parser.add_argument("--replace", action="store_true", help="overwrite an existing Docks/<pack-id>/ folder")
    args = parser.parse_args()

    failed = False
    DOCKS_DIR.mkdir(exist_ok=True)
    for source in args.packs:
        with tempfile.TemporaryDirectory(prefix="dockimport-") as tmp:
            try:
                pack_id = stage(source, Path(tmp))
            except DockRuleError as error:
                print(f"FAILED  {source}")
                for problem in error.problems:
                    print(f"        {problem}")
                failed = True
                continue
            target = DOCKS_DIR / pack_id
            if target.exists():
                if not args.replace:
                    print(f"FAILED  {source}")
                    print(f"        Docks/{pack_id} already exists (use --replace to overwrite)")
                    failed = True
                    continue
                shutil.rmtree(target)
            shutil.move(str(Path(tmp) / pack_id), target)
            print(f"imported  {pack_id}  ->  Docks/{pack_id}/")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
