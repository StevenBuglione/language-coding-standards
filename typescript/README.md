# TypeScript template

Reference implementation of the harness contract in [`docs/CONTRACTS.md`](../docs/CONTRACTS.md):
eleven strict gates (`verify.sh`) wrapped around the canonical warehouse-order
domain, plus `bad_examples/` fixtures that prove every gate bites.

## Use this template (clone → rename → go)

1. Copy the `typescript/` directory into your project (or copy it and rename the folder).
2. Rename the package: update `name` in `package.json`, and — if you rename or
   regroup directories under `src/` — mirror those paths in `tsconfig.json`
   `include`, `.dependency-cruiser.cjs` layer rules, `knip.json`, and the
   `mutate` glob in `stryker.config.json`.
3. Delete `bad_examples/` only if you also delete the `negative` phase — a gate
   without its fixture is a gate you cannot trust. Keeping both is the point.
4. Add your runtime dependencies (`pnpm add <pkg>`), commit the regenerated
   `pnpm-lock.yaml`. Quality tools stay devDependencies; installs are always
   `--frozen-lockfile`.
5. Run everything locally, hermetically: `docker compose run --rm typescript`
   from the repository root. Iterate until every GATE prints PASS.

Tool-by-tool rationale, thresholds, and deliberate non-enforcements live in
[`LANG_SPEC.md`](LANG_SPEC.md). The philosophy behind "CI is the style guide"
lives in [`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md).
