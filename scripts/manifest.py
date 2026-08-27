#!/usr/bin/env python3
"""Load standards/languages.yaml and select languages for verification.

The YAML file is JSON-compatible so the loader stays stdlib-only.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "standards" / "languages.yaml"
VALID_STATES = ("planned", "experimental", "candidate", "reference", "deprecated")
IMPLEMENTED_STATES = ("experimental", "candidate", "reference")
EXIT_USAGE = 64


@dataclass(frozen=True)
class Image:
    repository: str
    tag: str | None
    digest: str | None


@dataclass(frozen=True)
class Language:
    id: str
    display_name: str
    state: str
    folder: str
    verifier: str | None
    workflow: str | None
    dockerfile: str | None
    spec: str | None
    owner: str
    toolchain: str
    compose_service: str | None
    artifact: str
    os: tuple[str, ...]
    image: Image
    required_capabilities: tuple[str, ...]
    in_default: bool


def load(path: Path = DEFAULT_MANIFEST) -> dict[str, Language]:
    """Load the language map, keyed by id, in deterministic id order."""
    payload = json.loads(path.read_text(encoding="utf-8"))
    languages: dict[str, Language] = {}
    raw = payload["languages"]
    for lang_id in sorted(raw):
        item = raw[lang_id]
        image = item.get("image") or {}
        languages[lang_id] = Language(
            id=lang_id,
            display_name=item["displayName"],
            state=item["state"],
            folder=item["folder"],
            verifier=item.get("verifier"),
            workflow=item.get("workflow"),
            dockerfile=item.get("dockerfile"),
            spec=item.get("spec"),
            owner=item.get("owner", "unassigned"),
            toolchain=item.get("toolchain", ""),
            compose_service=item.get("composeService"),
            artifact=item.get("artifact", ""),
            os=tuple(item.get("os") or ["linux"]),
            image=Image(
                repository=image.get("repository", ""),
                tag=image.get("tag"),
                digest=image.get("digest"),
            ),
            required_capabilities=tuple(item.get("requiredCapabilities") or ()),
            in_default=bool(item.get("inDefault", True)),
        )
        if languages[lang_id].state not in VALID_STATES:
            raise ValueError(f"{lang_id}: invalid state {languages[lang_id].state!r}")
    return languages


def select(
    ids: Sequence[str] | None = None,
    *,
    states: Sequence[str] | None = None,
    capability: str | None = None,
    languages: dict[str, Language] | None = None,
) -> list[Language]:
    """Select languages. Default: implemented states, sorted by id."""
    catalog = languages if languages is not None else load()
    if ids:
        seen: set[str] = set()
        selected: list[Language] = []
        for lang_id in ids:
            if lang_id in seen:
                raise UsageError(f"duplicate language: {lang_id}")
            seen.add(lang_id)
            if lang_id not in catalog:
                raise UsageError(f"unknown language: {lang_id}")
            selected.append(catalog[lang_id])
        return selected

    wanted_states = tuple(states) if states else IMPLEMENTED_STATES
    selected = [lang for lang in catalog.values() if lang.state in wanted_states]
    if states is None and not ids:
        selected = [lang for lang in selected if lang.in_default]
    if capability:
        selected = [lang for lang in selected if capability in lang.required_capabilities]
    return selected


class UsageError(Exception):
    """CLI usage error (exit 64)."""


def validate_on_disk(root: Path, languages: dict[str, Language] | None = None) -> list[str]:
    """Return consistency errors for candidate/reference packs."""
    catalog = languages if languages is not None else load()
    errors: list[str] = []
    for lang in catalog.values():
        if lang.state not in {"candidate", "reference"}:
            continue
        required = {
            "directory": root / lang.folder,
            "Dockerfile": root / (lang.dockerfile or f"{lang.folder}/Dockerfile"),
            "verifier": root / (lang.verifier or f"{lang.folder}/verify.sh"),
            "spec": root / (lang.spec or f"{lang.folder}/LANG_SPEC.md"),
        }
        if lang.workflow:
            required["workflow"] = root / lang.workflow
        for label, path in required.items():
            if not path.exists():
                errors.append(f"{lang.id} ({lang.state}): missing {label} at {path}")
    return errors


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Select languages from the root manifest")
    parser.add_argument("languages", nargs="*", help="language ids (default: implemented)")
    parser.add_argument("--list", action="store_true", help="print selected ids")
    parser.add_argument("--state", action="append", dest="states", help="filter by state")
    parser.add_argument("--capability", help="filter languages requiring this capability")
    parser.add_argument("--json", help="write JSON to path, or - for stdout")
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="manifest path")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        catalog = load(Path(args.manifest))
        selected = select(
            args.languages or None,
            states=args.states,
            capability=args.capability,
            languages=catalog,
        )
    except UsageError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_USAGE
    except (OSError, json.JSONDecodeError, KeyError, ValueError) as exc:
        print(f"manifest error: {exc}", file=sys.stderr)
        return 1

    if not selected:
        print("no languages selected", file=sys.stderr)
        return 1

    if args.json:
        payload = {
            "schemaVersion": 1,
            "languages": [
                {
                    "id": lang.id,
                    "displayName": lang.display_name,
                    "state": lang.state,
                    "folder": lang.folder,
                    "verifier": lang.verifier,
                    "workflow": lang.workflow,
                    "composeService": lang.compose_service,
                }
                for lang in selected
            ],
        }
        text = json.dumps(payload, indent=2) + "\n"
        if args.json == "-":
            sys.stdout.write(text)
            return 0 if not args.list else 0
        path = Path(args.json)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        if not args.list:
            return 0

    for lang in selected:
        print(lang.id)
    return 0


if __name__ == "__main__":
    sys.exit(main())
