# Negative fixtures

One subdirectory per gated rule class. Each fixture is deliberately broken code
that its gate must reject; `assert.sh` proves every rejection still happens
(the `negative` phase of `verify.sh`). Fixtures are excluded from the main
tooling globs via `extend-exclude` — never via inline suppressions.

| fixture        | gate     | expected signal                        |
| -------------- | -------- | -------------------------------------- |
| too_complex    | lint     | `PLR0912` (>8 branches)                |
| type_violation | types    | `reportArgumentType` (basedpyright)    |
| arch_violation | arch     | `Broken contracts` (import-linter)     |
| dead_code      | deadcode | `unused function 'orphaned_helper'`    |
| insecure       | lint     | `S105` (hardcoded password string)     |
| printing       | lint     | `T201` (`print` call)                  |
| naive_datetime | lint     | `DTZ005` (tz-naive `datetime.now()`)   |
| todo_comment   | lint     | `TD003` (TODO without issue link)      |
| unformatted    | format   | `would be reformatted` (ruff format)   |

Notes:

- The arch fixture cannot live outside the package for import-linter to see;
  `assert.sh` copies it into `src/warehouse/domain/`, runs the gate, and
  removes it again in a trap.
- The dead-code fixture is probed at vulture's function confidence (60). The
  repo gate itself keeps `--min-confidence 80` per the toolchain brief; see
  LANG_SPEC.md for the trade-off.
