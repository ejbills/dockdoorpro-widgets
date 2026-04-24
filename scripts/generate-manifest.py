#!/usr/bin/env python3
"""Generate manifest.json from all widget.json files."""
import hashlib
import json
from pathlib import Path


def sha256_of_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_of_sources(widget_dir: Path) -> str:
    """Hash all source files so the digest only changes when code changes."""
    h = hashlib.sha256()
    for src in sorted(widget_dir.iterdir()):
        if src.suffix in (".swift", ".json"):
            h.update(src.name.encode())
            h.update(src.read_bytes())
    return h.hexdigest()


def main():
    root = Path(__file__).parent.parent
    widgets_dir = root / "Widgets"
    build_dir = root / "build"
    manifest = {"schemaVersion": 2, "widgets": []}

    if not widgets_dir.exists():
        print("No Widgets directory found")
        return

    for widget_dir in sorted(widgets_dir.iterdir()):
        widget_json = widget_dir / "widget.json"
        if not widget_json.exists():
            continue

        with open(widget_json) as f:
            meta = json.load(f)

        bundle_name = widget_dir.name + ".bundle"
        bundle_zip = build_dir / (bundle_name + ".zip")

        orientations = meta.get("orientations")
        if not orientations:
            print(f"  Skipping {widget_dir.name}: missing 'orientations' field")
            continue

        entry = {
            "id": meta["id"],
            "name": meta["name"],
            "author": meta.get("author", "unknown"),
            "description": meta.get("description", ""),
            "iconSymbol": meta.get("iconSymbol", "puzzlepiece"),
            "orientations": orientations,
            "bundleFilename": bundle_name + ".zip",
        }

        entry["sourceHash"] = sha256_of_sources(widget_dir)

        if bundle_zip.exists():
            entry["sha256"] = sha256_of_file(bundle_zip)
            entry["bundleSize"] = bundle_zip.stat().st_size

        manifest["widgets"].append(entry)

    with open(root / "manifest.json", "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(f"Generated manifest with {len(manifest['widgets'])} widget(s)")


if __name__ == "__main__":
    main()
