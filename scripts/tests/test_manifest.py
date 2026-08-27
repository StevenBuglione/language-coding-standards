"""Tests for the root language manifest and verifier selection."""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PY = ROOT / "scripts" / "manifest.py"
if str(ROOT / "scripts") not in sys.path:
    sys.path.insert(0, str(ROOT / "scripts"))

import manifest  # noqa: E402


class ManifestLoadTests(unittest.TestCase):
    def test_default_selection_is_the_five_implemented_languages(self) -> None:
        ids = [lang.id for lang in manifest.select()]
        self.assertEqual(ids, ["go", "java", "python", "rust", "typescript"])

    def test_planned_languages_are_excluded_from_defaults(self) -> None:
        ids = {lang.id for lang in manifest.select()}
        self.assertNotIn("csharp", ids)
        self.assertNotIn("kotlin", ids)
        self.assertNotIn("swift", ids)

    def test_planned_filter_lists_only_planned(self) -> None:
        ids = [lang.id for lang in manifest.select(states=["planned"])]
        self.assertEqual(ids, ["csharp", "kotlin", "swift"])

    def test_unknown_language_exits_64(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MANIFEST_PY), "cobol"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 64, completed.stderr)

    def test_duplicate_language_exits_64(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MANIFEST_PY), "python", "python"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 64, completed.stderr)

    def test_zero_selection_fails(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MANIFEST_PY), "--state", "reference"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 1, completed.stderr)

    def test_list_prints_ids(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MANIFEST_PY), "--list"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(
            completed.stdout.strip().splitlines(),
            ["go", "java", "python", "rust", "typescript"],
        )

    def test_json_output_round_trip(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MANIFEST_PY), "--json", "-"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertEqual(
            [item["id"] for item in payload["languages"]],
            ["go", "java", "python", "rust", "typescript"],
        )

    def test_candidate_or_reference_must_have_required_files(self) -> None:
        errors = manifest.validate_on_disk(ROOT)
        blocking = [error for error in errors if "candidate" in error or "reference" in error]
        self.assertEqual(blocking, [])

    def test_compose_omits_planned_languages(self) -> None:
        text = (ROOT / "docker-compose.yml").read_text(encoding="utf-8")
        self.assertNotRegex(text, r"(?m)^\s+csharp:")
        self.assertNotRegex(text, r"(?m)^\s+kotlin:")
        self.assertNotRegex(text, r"(?m)^\s+swift:")
        for lang_id in ("go", "java", "python", "rust", "typescript"):
            self.assertRegex(text, rf"(?m)^\s+{lang_id}:")


if __name__ == "__main__":
    unittest.main()
