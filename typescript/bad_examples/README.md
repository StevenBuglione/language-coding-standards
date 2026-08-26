# Negative fixtures

One subdirectory per gated rule class. Each fixture is deliberately broken code
that its gate must reject; `assert.sh` proves every rejection still happens
(the `negative` phase of `verify.sh`). Fixtures are excluded from the main
tooling globs via native scoping — the eslint global ignore list,
`.prettierignore`, and tsconfig `include`/`exclude` — never via inline
suppressions.

| fixture          | gate     | expected signal                                |
| ---------------- | -------- | ---------------------------------------------- |
| too_complex      | lint     | `complexity` rule (>15 decision points)        |
| type_violation   | types    | `error TS2322` (tsc)                           |
| arch_violation   | arch     | `domain-no-outbound` rule (dependency-cruiser) |
| dead_code        | deadcode | unused file `_tmp_dead_code_fixture.ts` (knip) |
| dead_code_export | deadcode | unused export `_tmpDeadExportProbe` (knip)     |
| insecure         | lint     | `forbidden: eval()` message                    |
| printing         | lint     | `no-console` rule                              |
| naive_datetime   | lint     | `forbidden: new Date()` message                |
| todo_comment     | lint     | `no-warning-comments` rule                     |
| unformatted      | format   | `Code style issues found` (prettier --check)   |

Notes:

- Lint fixtures are asserted against eslint's `--format json` output, where
  every finding carries its machine-readable ruleId and message; the human
  formats are not API.
- The arch fixture cannot live outside `src/` for dependency-cruiser to see
  the anchored layer edges; its import is written relative to that
  destination. `assert.sh` copies it into `src/domain/`, runs the gate, and
  removes it again in a trap.
- Dead code is proven on both of knip's layers: the fixture copied into
  `src/` surfaces as an unused FILE, and a dead export appended to the
  reachable module `src/domain/sku.ts` surfaces as an unused EXPORT. The
  export-level probe holds only while `src/index.ts` forwards symbols by
  explicit name — an `export *` barrel at the entry would exempt every
  transitively forwarded symbol from knip's analysis. assert.sh backs up
  sku.ts before appending and restores it in its trap.
- Prettier has no ignore-bypass flag, so the format probe passes
  `--ignore-path /dev/null` to check the fixture despite `.prettierignore`
  excluding `bad_examples/`.
- `insecure` and `naive_datetime` are custom `no-restricted-syntax` bans
  (`eval()`, no-arg `new Date()`), because no maintained free TypeScript
  SAST exists; each carries a stable `forbidden:` message prefix that this
  manifest asserts against. See LANG_SPEC.md for the trade-off.
- `bad_examples/type_violation/` carries its own `tsconfig.json` so the
  types gate can be probed scoped to exactly that fixture with `tsc -p`;
  the shared `bad_examples/tsconfig.json` gives every other fixture a type
  program so type-aware eslint rules work under `--no-ignore`.
