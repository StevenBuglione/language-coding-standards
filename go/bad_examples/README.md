# Negative fixtures

One subdirectory per gated rule class. Each fixture is deliberately broken
code that its gate must reject; `assert.sh` proves every rejection still
happens (the `negative` phase of `verify.sh`). This directory is its own
nested Go module (`go.mod` lives here), so the parent module's `./...` never
reaches these files by construction — no inline suppressions involved.

| fixture        | gate     | expected signal                          |
| -------------- | -------- | ---------------------------------------- |
| too_complex    | lint     | `cyclop` (>10 decision points)           |
| type_violation | types    | `cannot use ... as int value` (go build) |
| arch_violation | arch     | `depguard` (domain importing adapters)   |
| dead_code      | lint     | `is unused` (unused linter)              |
| insecure       | lint     | `G101` (hardcoded credential, gosec)     |
| printing       | lint     | `forbidigo` (`fmt.Print*` outside cmd/)  |
| naive_datetime | lint     | `forbidigo` (`time.Now` outside clock.go)|
| todo_comment   | lint     | `TODO` marker reported by the grep ban   |
| unformatted    | format   | unified diff (gofumpt/gci rewrite)       |

Notes:

- The lint/format probes run tools INSIDE this nested module with an explicit
  `-c ../.golangci.yaml`; text output is color-free by config so the
  `(lintername)` suffixes stay stable to grep.
- The arch fixture imports `warehouse/internal/adapters`, which is only legal
  from inside the parent module; `assert.sh` copies it into
  `internal/domain/` for one depguard-only run and removes it in a trap —
  the same trick the python template uses for import-linter.
- The TODO/FIXME ban is a grep step inside verify.sh's lint phase (Go has no
  native linter for unfinished-work markers worth the dependency), so its
  fixture is probed with that same grep rather than golangci-lint.
