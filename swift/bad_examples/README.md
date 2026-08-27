# Negative fixtures

One subdirectory per gated rule class. Each fixture is deliberately broken
code that its gate must reject; `assert.sh` proves every rejection still
happens (the `negative-fixtures` capability of `verify.sh`). Fixtures are
excluded from the main package by living outside `Sources/` and `Tests/` —
never via inline suppressions.

| fixture        | gate    | expected signal                                      |
| -------------- | ------- | ---------------------------------------------------- |
| unformatted    | format  | `swift format lint --strict` nonzero (when present)  |
| type_violation | compile | Swift compiler type error (`cannot convert value`)   |

This pack is experimental. Lint, architecture, dead-code, and SAST fixtures
are not claimed until those detectors are wired.
