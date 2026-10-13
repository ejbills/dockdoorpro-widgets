#!/usr/bin/env python3
"""Validate every Docks/<pack-id>/ folder against the shared rules in dock_rules.py.

Runs in CI before anything is compiled. Prints GitHub error annotations and
exits non-zero on any violation.
"""
import sys
from pathlib import Path

from dock_rules import DockRuleError, IGNORED_ENTRIES, validate


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    docks_dir = root / "Docks"
    failed = False
    count = 0

    if docks_dir.is_dir():
        for folder in sorted(docks_dir.iterdir()):
            if folder.name in IGNORED_ENTRIES:
                continue
            relative = folder.relative_to(root)
            if folder.is_symlink() or not folder.is_dir():
                print(f"::error file={relative}::Docks/ may only contain dock folders")
                failed = True
                continue
            try:
                pack = validate(folder)
            except DockRuleError as error:
                for problem in error.problems:
                    print(f"::error file={relative}/pack.json::{problem}")
                failed = True
                continue
            count += 1
            print(f"ok  {folder.name} ({pack['name']})")

    if failed:
        return 1
    print(f"All {count} docks pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
