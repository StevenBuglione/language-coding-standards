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
    def test_default_selection_is_the_five_default_languages(self) -> None:
        ids = [lang.id for lang in manifest.select()]
        self.assertEqual(ids, ["go", "java", "python", "rust", "typescript"])

    def test_in_default_false_is_excluded_even_if_implemented(self) -> None:
        selected = [item.id for item in manifest.select()]
        for lang in manifest.load().values():
            if not lang.in_default:
                self.assertNotIn(lang.id, selected)

    def test_opted_out_languages_are_excluded_from_defaults(self) -> None:
        ids = {lang.id for lang in manifest.select()}
        self.assertNotIn("csharp", ids)
        self.assertNotIn("kotlin", ids)
        self.assertNotIn("swift", ids)

    def test_planned_filter_is_empty_when_no_pack_is_planned(self) -> None:
        ids = [lang.id for lang in manifest.select(states=["planned"])]
        self.assertEqual(ids, [])

    def test_unknown_language_exits_64(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MANIFEST_PY), "cobol"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 64, completed.stderr)

    def test_unknown_state_exits_64(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MANIFEST_PY), "--state", "unknown"],
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

    def test_every_implemented_pack_matches_the_manifest(self) -> None:
        self.assertEqual(manifest.validate_on_disk(ROOT), [])

    def test_check_cli_validates_repository_state(self) -> None:
        completed = subprocess.run(
            [sys.executable, str(MANIFEST_PY), "--check"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout.strip(), "manifest: PASS")

    def test_compose_omits_opted_out_languages(self) -> None:
        text = (ROOT / "docker-compose.yml").read_text(encoding="utf-8")
        self.assertNotRegex(text, r"(?m)^\s+csharp:")
        self.assertNotRegex(text, r"(?m)^\s+kotlin:")
        self.assertNotRegex(text, r"(?m)^\s+swift:")
        for lang_id in ("go", "java", "python", "rust", "typescript"):
            self.assertRegex(text, rf"(?m)^\s+{lang_id}:")


if __name__ == "__main__":
    unittest.main()
