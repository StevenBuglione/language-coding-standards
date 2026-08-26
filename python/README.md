# Python template

Reference implementation of the harness contract in [`docs/CONTRACTS.md`](../docs/CONTRACTS.md):
eleven strict gates (`verify.sh`) wrapped around the canonical warehouse-order
domain, plus `bad_examples/` fixtures that prove every gate bites.

## Use this template (clone → rename → go)

1. Copy the `python/` directory into your project (or copy it and rename the folder).
2. Rename the package: move `src/warehouse` to `src/<your_package>`, update
   `root_package`, `[tool.importlinter]` contract module names,
   `[tool.basedpyright] include`, the `--cov=<pkg>` flag in `verify.sh`, and
   the project name in `pyproject.toml`.
3. Delete `bad_examples/` only if you also delete the `negative` phase — a gate
   without its fixture is a gate you cannot trust. Keeping both is the point.
4. Regenerate the lockfile for your dependency set: `uv lock`, commit `uv.lock`.
5. Run everything locally, hermetically: `docker compose run --rm python`
   from the repository root. Iterate until every GATE prints PASS.

Tool-by-tool rationale, thresholds, and deliberate non-enforcements live in
[`LANG_SPEC.md`](LANG_SPEC.md). The philosophy behind "CI is the style guide"
lives in [`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md).
