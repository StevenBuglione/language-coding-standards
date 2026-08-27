"""Tests for the language-independent contract v2 schema validator.

These tests exercise the validator and the on-disk suite files. They do not
run language packs. Current implementations are expected to fail these
vectors until WP4.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

V2_DIR = Path(__file__).resolve().parents[1]
if str(V2_DIR) not in sys.path:
    sys.path.insert(0, str(V2_DIR))

import validate  # noqa: E402


class ValidateSuiteTests(unittest.TestCase):
    def test_rejects_missing_contract_version(self) -> None:
        errors = validate.validate_suite(
            {"suite": "money", "cases": [_minimal_ok_case()]},
        )
        self.assertTrue(any("contractVersion" in error for error in errors), errors)

    def test_rejects_wrong_contract_version(self) -> None:
        errors = validate.validate_suite(
            {
                "contractVersion": "1",
                "suite": "money",
                "cases": [_minimal_ok_case()],
            },
        )
        self.assertTrue(any("contractVersion" in error for error in errors), errors)

    def test_rejects_empty_cases(self) -> None:
        errors = validate.validate_suite(
            {"contractVersion": "2", "suite": "money", "cases": []},
        )
        self.assertTrue(any("cases" in error for error in errors), errors)

    def test_rejects_duplicate_case_ids(self) -> None:
        case = _minimal_ok_case()
        errors = validate.validate_suite(
            {"contractVersion": "2", "suite": "money", "cases": [case, dict(case)]},
        )
        self.assertTrue(any("duplicate" in error for error in errors), errors)

    def test_rejects_unknown_operation(self) -> None:
        case = _minimal_ok_case()
        case["operation"] = "money.delete"
        errors = validate.validate_suite(
            {"contractVersion": "2", "suite": "money", "cases": [case]},
        )
        self.assertTrue(any("operation" in error for error in errors), errors)

    def test_rejects_error_outcome_without_error_code(self) -> None:
        case = _minimal_ok_case()
        case["expect"] = {"outcome": "error"}
        errors = validate.validate_suite(
            {"contractVersion": "2", "suite": "money", "cases": [case]},
        )
        self.assertTrue(any("error" in error for error in errors), errors)

    def test_rejects_ok_outcome_with_error_code(self) -> None:
        case = _minimal_ok_case()
        case["expect"]["error"] = "InvalidOrder"
        errors = validate.validate_suite(
            {"contractVersion": "2", "suite": "money", "cases": [case]},
        )
        self.assertTrue(any("error" in error for error in errors), errors)

    def test_rejects_unknown_error_code(self) -> None:
        case = _minimal_ok_case()
        case["expect"] = {"outcome": "error", "error": "Oops"}
        errors = validate.validate_suite(
            {"contractVersion": "2", "suite": "money", "cases": [case]},
        )
        self.assertTrue(any("Oops" in error or "error" in error for error in errors), errors)

    def test_accepts_minimal_valid_suite(self) -> None:
        errors = validate.validate_suite(
            {
                "contractVersion": "2",
                "suite": "money",
                "cases": [_minimal_ok_case()],
            },
        )
        self.assertEqual(errors, [])

    def test_rejects_ok_outcome_without_result(self) -> None:
        case = _minimal_ok_case()
        case["expect"] = {"outcome": "ok"}
        errors = validate.validate_suite(
            {"contractVersion": "2", "suite": "money", "cases": [case]},
        )
        self.assertTrue(any("result" in error for error in errors), errors)


class OnDiskContractTests(unittest.TestCase):
    def test_schema_file_is_json_object(self) -> None:
        schema = json.loads((V2_DIR / "schema.json").read_text(encoding="utf-8"))
        self.assertIsInstance(schema, dict)
        self.assertIn("$schema", schema)
        self.assertIn("properties", schema)

    def test_all_suite_files_validate(self) -> None:
        errors = validate.validate_tree(V2_DIR)
        self.assertEqual(errors, [], "\n".join(errors))

    def test_catalog_ids_are_present(self) -> None:
        catalog = json.loads((V2_DIR / "catalog.json").read_text(encoding="utf-8"))
        required = catalog["requiredCaseIds"]
        found = validate.collect_case_ids(V2_DIR)
        missing = [case_id for case_id in required if case_id not in found]
        self.assertEqual(missing, [])

    def test_iso_style_zzz_is_accepted(self) -> None:
        case = _case_by_id("money.construct.valid.isoStyleZzz")
        self.assertEqual(case["expect"]["outcome"], "ok")
        self.assertEqual(case["input"]["currency"], "ZZZ")

    def test_quantity_boolean_true_is_rejected(self) -> None:
        case = _case_by_id("quantity.construct.invalid.booleanTrue")
        self.assertEqual(case["input"]["value"], True)
        self.assertEqual(case["expect"]["error"], "InvalidOrder")

    def test_success_place_order_requires_paid(self) -> None:
        case = _case_by_id("placeOrder.execute.success.persistsPaid")
        self.assertEqual(case["expect"]["outcome"], "ok")
        self.assertEqual(case["expect"]["result"]["order"]["status"], "PAID")

    def test_payment_decline_releases_reservation(self) -> None:
        case = _case_by_id("placeOrder.execute.paymentDecline.releasesReservation")
        self.assertEqual(case["expect"]["error"], "PaymentDeclined")
        self.assertGreaterEqual(int(case["expect"]["result"]["effects"]["releaseCalls"]), 1)
        self.assertEqual(int(case["expect"]["result"]["effects"]["saveCalls"]), 0)

    def test_gaps_reference_existing_cases_and_baseline(self) -> None:
        gaps = json.loads((V2_DIR / "gaps.json").read_text(encoding="utf-8"))
        self.assertEqual(
            gaps["baselineSha"],
            "e856a5add491f1eebd58273224945a0f4b3ba797",
        )
        found = validate.collect_case_ids(V2_DIR)
        missing = [case_id for case_id in gaps["failingCaseIds"] if case_id not in found]
        self.assertEqual(missing, [])
        self.assertIn("placeOrder.execute.success.persistsPaid", gaps["failingCaseIds"])

    def test_cli_exits_zero_on_shipped_tree(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(V2_DIR / "validate.py"), "--dir", str(V2_DIR)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertIn("PASS", completed.stdout)

    def test_cli_exits_nonzero_when_required_files_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            completed = subprocess.run(
                [sys.executable, str(V2_DIR / "validate.py"), "--dir", tmp],
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertEqual(completed.returncode, 1, completed.stdout + completed.stderr)
        self.assertIn("FAIL", completed.stdout)


def _minimal_ok_case() -> dict[str, object]:
    return {
        "id": "money.construct.valid.zero",
        "description": "Zero minor units is valid money.",
        "operation": "money.construct",
        "input": {"minorUnits": "0", "currency": "USD"},
        "expect": {
            "outcome": "ok",
            "result": {"minorUnits": "0", "currency": "USD"},
        },
    }


def _case_by_id(case_id: str) -> dict[str, object]:
    for path in sorted((V2_DIR / "suites").glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        for case in payload["cases"]:
            if case["id"] == case_id:
                return case
    raise AssertionError(f"missing case {case_id}")


if __name__ == "__main__":
    unittest.main()
