#!/usr/bin/env python3
"""Generate build/docks.json and build/docks/ from the Docks/ folders.

docks.json is { "schemaVersion": 1, "docks": [...] }: every pack.json with a
relative "url" added to each asset ("docks/<pack-id>-<sha16>.<ext>", relative to
docks.json) and `author.isOfficial` set from verified-docks.json. Output is
deterministic: verified docks first by name, then the rest newest createdAt
first. Widgets and manifest.json are untouched.
"""
import json
import shutil
import sys
from pathlib import Path

from dock_rules import DockRuleError, IGNORED_ENTRIES, asset_path, load_verified, validate

SCHEMA_VERSION = 1


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    docks_dir = root / "Docks"
    build_dir = root / "build"
    images_dir = build_dir / "docks"

    if images_dir.exists():
        shutil.rmtree(images_dir)
    images_dir.mkdir(parents=True)

    try:
        verified = load_verified(root)
    except DockRuleError as error:
        print(error, file=sys.stderr)
        return 1

    packs = []
    if docks_dir.is_dir():
        for folder in sorted(docks_dir.iterdir()):
            if folder.name in IGNORED_ENTRIES:
                continue
            try:
                pack = validate(folder)
            except DockRuleError as error:
                print(f"{folder.name}: {error}", file=sys.stderr)
                return 1
            for key, asset in pack.get("assets", {}).items():
                source = asset_path(folder, key, asset)
                filename = f"{pack['id']}-{asset['sha256'][:16]}{source.suffix}"
                shutil.copyfile(source, images_dir / filename)
                asset["url"] = f"docks/{filename}"
            pack["author"]["isOfficial"] = pack["id"] in verified
            packs.append(pack)

    first = sorted((p for p in packs if p["author"]["isOfficial"]), key=lambda p: (p["name"].lower(), p["id"]))
    rest = sorted((p for p in packs if not p["author"]["isOfficial"]), key=lambda p: p["id"])
    rest.sort(key=lambda p: p.get("createdAt", ""), reverse=True)

    catalog = {"schemaVersion": SCHEMA_VERSION, "docks": first + rest}
    out = build_dir / "docks.json"
    out.write_text(json.dumps(catalog, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Generated docks.json with {len(catalog['docks'])} dock(s), {len(list(images_dir.iterdir()))} image(s), {out.stat().st_size} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
