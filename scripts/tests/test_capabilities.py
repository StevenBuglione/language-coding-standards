"""Tests for the shared capability expander used by every verify.sh."""

from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPANDER = ROOT / "scripts" / "lib" / "capabilities.sh"
BASH = shutil.which("bash")


def bash_path(path: Path) -> str:
    text = str(path.resolve())
    probe = subprocess.run(
        [BASH, "-lc", "uname -s"],
        check=False,
        capture_output=True,
        text=True,
    )
    linux = "Linux" in (probe.stdout or "")
    if len(text) >= 2 and text[1] == ":":
        drive = text[0].lower()
        rest = text[2:].replace("\\", "/")
        if linux:
            return f"/mnt/{drive}{rest}"
        return f"/{drive}{rest}"
    return text.replace("\\", "/")


@unittest.skipUnless(BASH, "bash is required to run the expander")
class ExpandCapabilitiesTests(unittest.TestCase):
    def expand(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [BASH, bash_path(EXPANDER), *args],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_default_set_excludes_mutation(self) -> None:
        completed = self.expand()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        names = completed.stdout.strip().splitlines()
        self.assertIn("bootstrap", names)
        self.assertIn("package", names)
        self.assertIn("unit", names)
        self.assertNotIn("mutation", names)
        self.assertNotIn("deps", names)

    def test_test_alias_expands_to_three_capabilities_in_order(self) -> None:
        completed = self.expand("test")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(
            completed.stdout.strip().splitlines(),
            ["unit", "property", "integration"],
        )

    def test_security_alias_splits_sast_and_vulnerability(self) -> None:
        completed = self.expand("security")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(
            completed.stdout.strip().splitlines(),
            ["sast", "dependency-vulnerability"],
        )

    def test_deadcode_alias_is_dead_code_only(self) -> None:
        completed = self.expand("deadcode")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(completed.stdout.strip().splitlines(), ["dead-code"])

    def test_deps_expands_to_bootstrap_and_lock_integrity(self) -> None:
        completed = self.expand("deps")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(
            completed.stdout.strip().splitlines(),
            ["bootstrap", "lock-integrity"],
        )

    def test_deps_hygiene_does_not_map_to_dead_code(self) -> None:
        completed = self.expand("deps-hygiene")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        names = completed.stdout.strip().splitlines()
        self.assertEqual(names, ["dependency-policy", "lock-integrity"])
        self.assertNotIn("dead-code", names)

    def test_argument_order_is_canonical(self) -> None:
        completed = self.expand("coverage", "format", "unit")
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(
            completed.stdout.strip().splitlines(),
            ["format", "unit", "coverage"],
        )

    def test_unknown_name_exits_64(self) -> None:
        completed = self.expand("feelings")
        self.assertEqual(completed.returncode, 64)
        self.assertIn("unknown capability", completed.stderr)

    def test_duplicate_after_alias_expansion_exits_64(self) -> None:
        completed = self.expand("unit", "test")
        self.assertEqual(completed.returncode, 64)
        self.assertIn("duplicate capability", completed.stderr)

    def test_language_copies_match_canonical(self) -> None:
        canonical = EXPANDER.read_text(encoding="utf-8")
        for lang in ("go", "java", "python", "rust", "typescript"):
            copy = ROOT / lang / "capabilities.sh"
            self.assertTrue(copy.exists(), f"missing {copy}")
            self.assertEqual(copy.read_text(encoding="utf-8"), canonical)


if __name__ == "__main__":
    unittest.main()
