#!/usr/bin/env python3
"""Load and validate the root language-pack manifest.

The YAML-named file is deliberately JSON-compatible so this tool remains
stdlib-only and can run before any language environment is bootstrapped.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
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

    @property
    def reference(self) -> str:
        """Return the tag-based image reference declared by the manifest."""
        if not self.repository:
            return ""
        return f"{self.repository}:{self.tag}" if self.tag else self.repository


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


class UsageError(Exception):
    """CLI usage error (exit 64)."""


def load(path: Path = DEFAULT_MANIFEST) -> dict[str, Language]:
    """Load the language map, keyed by id, in deterministic id order."""
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != 1:
        raise ValueError(f"unsupported schemaVersion: {payload.get('schemaVersion')!r}")
    if tuple(payload.get("defaultStates") or ()) != IMPLEMENTED_STATES:
        raise ValueError(
            "defaultStates must exactly match implemented states: "
            f"{list(IMPLEMENTED_STATES)!r}"
        )

    raw = payload.get("languages")
    if not isinstance(raw, dict) or not raw:
        raise ValueError("languages must be a non-empty object")

    languages: dict[str, Language] = {}
    for lang_id in sorted(raw):
        item = raw[lang_id]
        image = item.get("image") or {}
        language = Language(
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
        if language.state not in VALID_STATES:
            raise ValueError(f"{lang_id}: invalid state {language.state!r}")
        if language.id != language.folder:
            raise ValueError(f"{lang_id}: folder must equal language id")
        if not language.display_name or not language.toolchain or not language.artifact:
            raise ValueError(f"{lang_id}: displayName, toolchain, and artifact are required")
        languages[lang_id] = language
    return languages


def select(
    ids: Sequence[str] | None = None,
    *,
    states: Sequence[str] | None = None,
    capability: str | None = None,
    languages: dict[str, Language] | None = None,
) -> list[Language]:
    """Select languages. Default: in-default implemented states, sorted by id."""
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
    invalid_states = sorted(set(wanted_states) - set(VALID_STATES))
    if invalid_states:
        raise UsageError(f"unknown state: {', '.join(invalid_states)}")
    selected = [lang for lang in catalog.values() if lang.state in wanted_states]
    if states is None:
        selected = [lang for lang in selected if lang.in_default]
    if capability:
        selected = [lang for lang in selected if capability in lang.required_capabilities]
    return selected


def _safe_path(root: Path, relative: str, *, language: str, label: str) -> tuple[Path, str | None]:
    candidate = (root / relative).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return candidate, f"{language}: {label} escapes repository root: {relative}"
    return candidate, None


def _shell_array(path: Path, name: str) -> tuple[str, ...]:
    text = path.read_text(encoding="utf-8")
    match = re.search(rf"(?ms)^\s*{re.escape(name)}=\(\s*(.*?)^\s*\)", text)
    if match is None:
        raise ValueError(f"{path}: missing {name} array")
    values: list[str] = []
    for line in match.group(1).splitlines():
        token = line.split("#", 1)[0].strip()
        if token:
            values.extend(shlex.split(token))
    return tuple(values)


def _first_from_image(path: Path) -> str | None:
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        tokens = shlex.split(line, comments=True)
        if not tokens or tokens[0].upper() != "FROM":
            continue
        index = 1
        if index < len(tokens) and tokens[index].startswith("--platform="):
            index += 1
        return tokens[index] if index < len(tokens) else None
    return None


def validate_on_disk(root: Path, languages: dict[str, Language] | None = None) -> list[str]:
    """Return consistency errors for every implemented language pack."""
    catalog = languages if languages is not None else load()
    errors: list[str] = []
    seen_folders: dict[str, str] = {}
    seen_workflows: dict[str, str] = {}

    compose_text = ""
    compose_path = root / "docker-compose.yml"
    if compose_path.exists():
        compose_text = compose_path.read_text(encoding="utf-8")

    for lang in catalog.values():
        if lang.state not in IMPLEMENTED_STATES:
            continue

        if lang.folder in seen_folders:
            errors.append(
                f"{lang.id}: folder {lang.folder!r} also belongs to {seen_folders[lang.folder]}"
            )
        seen_folders[lang.folder] = lang.id
        if lang.workflow:
            if lang.workflow in seen_workflows:
                errors.append(
                    f"{lang.id}: workflow {lang.workflow!r} also belongs to "
                    f"{seen_workflows[lang.workflow]}"
                )
            seen_workflows[lang.workflow] = lang.id

        relative_paths = {
            "directory": lang.folder,
            "Dockerfile": lang.dockerfile or f"{lang.folder}/Dockerfile",
            "verifier": lang.verifier or f"{lang.folder}/verify.sh",
            "spec": lang.spec or f"{lang.folder}/LANG_SPEC.md",
            "capabilities": f"{lang.folder}/capabilities.sh",
        }
        if lang.workflow:
            relative_paths["workflow"] = lang.workflow

        resolved: dict[str, Path] = {}
        for label, relative in relative_paths.items():
            path, path_error = _safe_path(root, relative, language=lang.id, label=label)
            if path_error:
                errors.append(path_error)
                continue
            resolved[label] = path
            if not path.exists():
                errors.append(f"{lang.id} ({lang.state}): missing {label} at {relative}")

        verifier = resolved.get("verifier")
        if verifier and verifier.exists() and not os.access(verifier, os.X_OK):
            errors.append(f"{lang.id}: verifier is not executable: {lang.verifier}")

        capabilities = resolved.get("capabilities")
        if capabilities and capabilities.exists():
            try:
                canonical = _shell_array(capabilities, "CANONICAL_CAPABILITIES")
            except (OSError, ValueError) as exc:
                errors.append(str(exc))
            else:
                duplicates = sorted(
                    {item for item in lang.required_capabilities if lang.required_capabilities.count(item) > 1}
                )
                unknown = sorted(set(lang.required_capabilities) - set(canonical))
                if not lang.required_capabilities:
                    errors.append(f"{lang.id}: requiredCapabilities must not be empty")
                if duplicates:
                    errors.append(f"{lang.id}: duplicate requiredCapabilities: {duplicates}")
                if unknown:
                    errors.append(f"{lang.id}: unknown requiredCapabilities: {unknown}")

        dockerfile = resolved.get("Dockerfile")
        expected_image = lang.image.reference
        if dockerfile and dockerfile.exists():
            actual_image = _first_from_image(dockerfile)
            if not expected_image:
                errors.append(f"{lang.id}: manifest image repository/tag is incomplete")
            elif actual_image != expected_image:
                errors.append(
                    f"{lang.id}: Dockerfile image {actual_image!r} != manifest {expected_image!r}"
                )

        workflow = resolved.get("workflow")
        if workflow and workflow.exists():
            workflow_text = workflow.read_text(encoding="utf-8")
            language_pattern = rf"(?m)^\s+language:\s*['\"]?{re.escape(lang.id)}['\"]?\s*$"
            image_pattern = rf"(?m)^\s+image:\s*['\"]?{re.escape(expected_image)}['\"]?\s*$"
            if not re.search(language_pattern, workflow_text):
                errors.append(f"{lang.id}: workflow does not pass language: {lang.id}")
            if expected_image and not re.search(image_pattern, workflow_text):
                errors.append(f"{lang.id}: workflow image does not match {expected_image}")

        if lang.compose_service:
            service_pattern = rf"(?m)^\s{{2}}{re.escape(lang.compose_service)}:\s*$"
            if not re.search(service_pattern, compose_text):
                errors.append(
                    f"{lang.id}: compose service {lang.compose_service!r} is missing"
                )

    return sorted(errors)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Select or validate language packs")
    parser.add_argument("languages", nargs="*", help="language ids (default: implemented)")
    parser.add_argument("--list", action="store_true", help="print selected ids")
    parser.add_argument("--check", action="store_true", help="validate manifest against repository files")
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
        if args.check:
            errors = validate_on_disk(ROOT, catalog)
            if errors:
                for error in errors:
                    print(f"manifest error: {error}", file=sys.stderr)
                return 1
            print("manifest: PASS")
            return 0
        selected = select(
            args.languages or None,
            states=args.states,
            capability=args.capability,
            languages=catalog,
        )
    except UsageError as exc:
        print(str(exc), file=sys.stderr)
        return EXIT_USAGE
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError) as exc:
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
            return 0
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
