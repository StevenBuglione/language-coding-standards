#!/usr/bin/env python3
"""Compare two clean artifact listings for WP7 reproducibility evidence.

This does not rebuild language containers. It records the comparison
protocol and fails if two provided directories differ after normalization.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def snapshot(root: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            rel = path.relative_to(root).as_posix()
            entries[rel] = file_digest(path)
    return entries


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("left")
    parser.add_argument("right")
    parser.add_argument("--json", default="-")
    args = parser.parse_args(argv)
    left = snapshot(Path(args.left))
    right = snapshot(Path(args.right))
    missing = sorted(set(left) - set(right))
    extra = sorted(set(right) - set(left))
    changed = sorted(name for name in set(left) & set(right) if left[name] != right[name])
    payload = {
        "equal": not (missing or extra or changed),
        "missingInRight": missing,
        "extraInRight": extra,
        "changed": changed,
    }
    text = json.dumps(payload, indent=2) + "\n"
    if args.json == "-":
        sys.stdout.write(text)
    else:
        Path(args.json).write_text(text, encoding="utf-8")
    return 0 if payload["equal"] else 1


if __name__ == "__main__":
    sys.exit(main())
