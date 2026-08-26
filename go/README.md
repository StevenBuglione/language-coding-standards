# Go template

Reference implementation of the harness contract in [`docs/CONTRACTS.md`](../docs/CONTRACTS.md):
eleven strict gates (`verify.sh`) wrapped around the canonical warehouse-order
domain, plus `bad_examples/` fixtures that prove every gate bites.

## Use this template (clone → rename → go)

1. Copy the `go/` directory into your project (or copy it and rename the folder).
2. Rename the module: update `module warehouse` in `go.mod`, rewrite
   `prefix(warehouse)` and `warehouse/internal/...` patterns in
   `.golangci.yaml`, fix import paths, and adjust
   `-coverpkg=./internal/...` in `verify.sh` if your layout differs.
3. Delete `bad_examples/` only if you also delete the `negative` phase — a gate
   without its fixture is a gate you cannot trust. Keeping both is the point.
4. Bump tool pins in one place: `verify.sh` (`GOLANGCI_LINT_VERSION`,
   `DEADCODE_VERSION`, `GOVULNCHECK_VERSION`); the compiler pin is the Docker
   image tag.
5. Run everything locally, hermetically: `docker compose run --rm go`
   from the repository root. Iterate until every GATE prints PASS.

Tool-by-tool rationale, thresholds, and deliberate non-enforcements live in
[`LANG_SPEC.md`](LANG_SPEC.md). The philosophy behind "CI is the style guide"
lives in [`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md).
