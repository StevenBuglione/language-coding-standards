# Rust template

Reference implementation of the harness contract in [`docs/CONTRACTS.md`](../docs/CONTRACTS.md):
eleven strict gates (`verify.sh`) wrapped around the canonical warehouse-order
domain, plus `bad_examples/` fixtures that prove every gate bites.

## Use this template (clone → rename → go)

1. Copy the `rust/` directory into your project (or copy it and rename the folder).
2. Rename the crates: change the `warehouse-*` names under `crates/`, the
   `[workspace.dependencies]` path entries in the root `Cargo.toml`, the
   `use warehouse_*` imports, and the `-p warehouse-*` arguments in
   `verify.sh`'s arch phase.
3. Delete `bad_examples/` only if you also delete the `negative` phase — a gate
   without its fixture is a gate you cannot trust. Keeping both is the point.
4. Commit the regenerated `Cargo.lock`; every cargo command runs `--locked`.
5. Re-measure coverage after your first green run and reset
   `COVERAGE_FLOOR` in `verify.sh` per the R3 rule; record the baseline in
   [`LANG_SPEC.md`](LANG_SPEC.md) Thresholds.
6. Run everything locally, hermetically: `docker compose run --rm rust`
   from the repository root. Iterate until every GATE prints PASS.

Tool-by-tool rationale, thresholds, and deliberate non-enforcements live in
[`LANG_SPEC.md`](LANG_SPEC.md). The philosophy behind "CI is the style guide"
lives in [`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md).
