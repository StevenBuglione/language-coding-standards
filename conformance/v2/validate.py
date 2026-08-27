#!/usr/bin/env python3
"""Validate contract-v2 conformance suites without executing language packs.

Stdlib only. Suite files are JSON documents that must match the structural
rules encoded here and documented by schema.json.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

CONTRACT_VERSION = "2"

OPERATIONS = frozenset(
    {
        "money.construct",
        "money.add",
        "money.times",
        "quantity.construct",
        "sku.construct",
        "order.construct",
        "order.pay",
        "order.ship",
        "placeOrder.execute",
        "repository.save",
        "repository.get",
    },
)

ERROR_CODES = frozenset(
    {
        "InvalidOrder",
        "InsufficientStock",
        "PaymentDeclined",
        "PersistenceConflict",
        "InfrastructureFailure",
        "CompensationFailure",
        "OrderAlreadyShipped",
    },
)

CASE_ID_PATTERN_MESSAGE = "case id must match [A-Za-z0-9][A-Za-z0-9._-]*"


def is_case_id(value: object) -> bool:
    """Return True when value is a stable case identifier."""
    if not isinstance(value, str) or not value:
        return False
    head, tail = value[0], value[1:]
    if not head.isalnum():
        return False
    return all(char.isalnum() or char in "._-" for char in tail)


def validate_suite(payload: object, *, source: str = "<suite>") -> list[str]:
    """Return human-readable errors for one suite document."""
    errors: list[str] = []
    prefix = f"{source}: "

    if not isinstance(payload, dict):
        return [f"{prefix}suite document must be a JSON object"]

    version = payload.get("contractVersion")
    if version != CONTRACT_VERSION:
        errors.append(f"{prefix}contractVersion must be {CONTRACT_VERSION!r}")

    suite = payload.get("suite")
    if not isinstance(suite, str) or not suite:
        errors.append(f"{prefix}suite must be a non-empty string")

    cases = payload.get("cases")
    if not isinstance(cases, list) or len(cases) == 0:
        errors.append(f"{prefix}cases must be a non-empty array")
        return errors

    seen_ids: set[str] = set()
    for index, case in enumerate(cases):
        errors.extend(_validate_case(case, source=source, index=index, seen_ids=seen_ids))
    return errors


def _validate_case(
    case: object,
    *,
    source: str,
    index: int,
    seen_ids: set[str],
) -> list[str]:
    prefix = f"{source} cases[{index}]: "
    if not isinstance(case, dict):
        return [f"{prefix}case must be a JSON object"]

    errors: list[str] = []
    case_id = case.get("id")
    if not is_case_id(case_id):
        errors.append(f"{prefix}{CASE_ID_PATTERN_MESSAGE}")
    elif case_id in seen_ids:
        errors.append(f"{prefix}duplicate case id {case_id!r}")
    else:
        seen_ids.add(str(case_id))

    description = case.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append(f"{prefix}description must be a non-empty string")

    operation = case.get("operation")
    if operation not in OPERATIONS:
        errors.append(f"{prefix}operation must be one of {sorted(OPERATIONS)}")

    given = case.get("given", {})
    if not isinstance(given, dict):
        errors.append(f"{prefix}given must be an object when present")

    if "input" not in case:
        errors.append(f"{prefix}input is required")
    elif not isinstance(case["input"], dict):
        errors.append(f"{prefix}input must be an object")

    expect = case.get("expect")
    if not isinstance(expect, dict):
        errors.append(f"{prefix}expect must be an object")
        return errors

    outcome = expect.get("outcome")
    if outcome not in {"ok", "error"}:
        errors.append(f"{prefix}expect.outcome must be 'ok' or 'error'")
        return errors

    if outcome == "error":
        error_code = expect.get("error")
        if error_code not in ERROR_CODES:
            errors.append(
                f"{prefix}expect.error is required and must be one of {sorted(ERROR_CODES)}",
            )
        if "result" in expect and expect["result"] is not None:
            result = expect["result"]
            if not isinstance(result, dict):
                errors.append(f"{prefix}expect.result must be an object when present")
    else:
        if "error" in expect:
            errors.append(f"{prefix}expect.error must be omitted when outcome is ok")
        result = expect.get("result")
        if not isinstance(result, dict):
            errors.append(f"{prefix}expect.result is required when outcome is ok")

    return errors


def collect_case_ids(root: Path) -> set[str]:
    """Collect case ids from every suite JSON file under root/suites."""
    ids: set[str] = set()
    for path in _suite_paths(root):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(payload, dict) and isinstance(payload.get("cases"), list):
            for case in payload["cases"]:
                if isinstance(case, dict) and isinstance(case.get("id"), str):
                    ids.add(case["id"])
    return ids


def validate_tree(root: Path) -> list[str]:
    """Validate schema, catalog, gaps, and every suite file under root."""
    errors: list[str] = []
    schema_path = root / "schema.json"
    catalog_path = root / "catalog.json"
    gaps_path = root / "gaps.json"
    suites_dir = root / "suites"

    for required in (schema_path, catalog_path, gaps_path, suites_dir):
        if not required.exists():
            errors.append(f"missing required path {required}")

    if errors:
        return errors

    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"{schema_path}: invalid JSON ({exc})"]
    if not isinstance(schema, dict) or "$schema" not in schema:
        errors.append(f"{schema_path}: schema must be a JSON object with $schema")

    try:
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"{catalog_path}: invalid JSON ({exc})"]
    required_ids = catalog.get("requiredCaseIds") if isinstance(catalog, dict) else None
    if not isinstance(required_ids, list) or not required_ids:
        errors.append(f"{catalog_path}: requiredCaseIds must be a non-empty array")
        required_ids = []

    try:
        gaps = json.loads(gaps_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return [f"{gaps_path}: invalid JSON ({exc})"]
    if not isinstance(gaps, dict):
        errors.append(f"{gaps_path}: gaps must be a JSON object")
        failing_ids: list[object] = []
    else:
        if gaps.get("baselineSha") != "e856a5add491f1eebd58273224945a0f4b3ba797":
            errors.append(f"{gaps_path}: baselineSha must record the audited SHA")
        failing_ids = gaps.get("failingCaseIds", [])
        if not isinstance(failing_ids, list) or not failing_ids:
            errors.append(f"{gaps_path}: failingCaseIds must be a non-empty array")
            failing_ids = []

    suite_paths = _suite_paths(root)
    if not suite_paths:
        errors.append(f"{suites_dir}: no suite JSON files found")

    found_ids: set[str] = set()
    for path in suite_paths:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{path}: invalid JSON ({exc})")
            continue
        errors.extend(validate_suite(payload, source=str(path)))
        if isinstance(payload, dict) and isinstance(payload.get("cases"), list):
            for case in payload["cases"]:
                if isinstance(case, dict) and isinstance(case.get("id"), str):
                    if case["id"] in found_ids:
                        errors.append(f"{path}: duplicate case id across suites: {case['id']}")
                    found_ids.add(case["id"])

    missing_required = [case_id for case_id in required_ids if case_id not in found_ids]
    if missing_required:
        errors.append(f"{catalog_path}: missing required cases: {missing_required}")

    missing_gaps = [case_id for case_id in failing_ids if case_id not in found_ids]
    if missing_gaps:
        errors.append(f"{gaps_path}: failingCaseIds not found in suites: {missing_gaps}")

    extra_catalog = [case_id for case_id in required_ids if not is_case_id(case_id)]
    if extra_catalog:
        errors.append(f"{catalog_path}: invalid requiredCaseIds: {extra_catalog}")

    return errors


def _suite_paths(root: Path) -> list[Path]:
    suites_dir = root / "suites"
    if not suites_dir.is_dir():
        return []
    return sorted(path for path in suites_dir.glob("*.json") if path.is_file())


def main(argv: list[str] | None = None) -> int:
    """CLI entry point. Exit 0 on PASS, 1 on FAIL."""
    parser = argparse.ArgumentParser(description="Validate contract v2 conformance suites")
    parser.add_argument(
        "--dir",
        default=str(Path(__file__).resolve().parent),
        help="conformance/v2 directory",
    )
    args = parser.parse_args(argv)
    root = Path(args.dir)
    errors = validate_tree(root)
    if errors:
        print("GATE conformance-schema: FAIL")
        for error in errors:
            print(error)
        return 1
    print("GATE conformance-schema: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
