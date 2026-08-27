"""Tests for the WP7 artifact comparison helper."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "reproducibility.py"


class ReproducibilityTests(unittest.TestCase):
    def test_identical_trees_are_equal(self) -> None:
        with tempfile.TemporaryDirectory() as left, tempfile.TemporaryDirectory() as right:
            Path(left, "a.bin").write_bytes(b"ok")
            Path(right, "a.bin").write_bytes(b"ok")
            completed = subprocess.run(
                [sys.executable, str(SCRIPT), left, right],
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)

    def test_changed_file_is_detected(self) -> None:
        with tempfile.TemporaryDirectory() as left, tempfile.TemporaryDirectory() as right:
            Path(left, "a.bin").write_bytes(b"ok")
            Path(right, "a.bin").write_bytes(b"no")
            completed = subprocess.run(
                [sys.executable, str(SCRIPT), left, right],
                check=False,
                capture_output=True,
                text=True,
            )
        self.assertEqual(completed.returncode, 1, completed.stdout)


if __name__ == "__main__":
    unittest.main()
