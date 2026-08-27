# Swift template

Experimental implementation of the harness contract in
[`docs/CONTRACTS.md`](../docs/CONTRACTS.md) v2: warehouse-order domain plus
`verify.sh` gates. **Evidence is Linux (`swift:6.0`) only. Apple platforms
are unproven.**

This pack is `experimental` and `inDefault: false`. It is not part of default
`scripts/verify-all.sh` or Compose until a maintainer opts in.

## Gates that currently prove work

- `bootstrap` — `swift package resolve`
- `format` — `swift format lint --strict` when the bundled formatter exists
- `compile` — `swift build --build-tests`
- `unit` — `swift test` (zero tests is a failure)
- `package` — `swift build -c release` plus a library artifact smoke
- `negative-fixtures` — `bad_examples/assert.sh`

Every other capability prints `SKIP_UNSUPPORTED` with a reason. Mutation is
skipped rather than simulated.

Tool-by-tool rationale lives in [`LANG_SPEC.md`](LANG_SPEC.md).
