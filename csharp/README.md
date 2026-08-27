# C# template (experimental)

Experimental implementation of the harness contract in [`docs/CONTRACTS.md`](../docs/CONTRACTS.md):
`verify.sh` capability gates around the canonical warehouse-order domain, plus
`bad_examples/` fixtures that prove format and compile detectors bite.

This pack is **not** in the default `verify-all` set (`inDefault: false`).

## Use this template (clone → rename → go)

1. Copy the `csharp/` directory into your project.
2. Rename the solution and projects; update `PackageId` in
   `src/Warehouse.Domain/Warehouse.Domain.csproj` and the `--cov` equivalent
   smoke in `verify.sh`'s `package` phase.
3. Delete `bad_examples/` only if you also delete the `negative-fixtures`
   phase — a gate without its fixture is a gate you cannot trust.
4. After changing package versions, run `dotnet restore --use-lock-file` and
   commit every `packages.lock.json`.
5. Run locally: `bash ./verify.sh` from `csharp/`, or in CI via the
   `csharp` workflow. Hermetic Docker: `docker build -t warehouse-csharp .`
   then mount this folder at `/workspace`.

Tool-by-tool rationale, thresholds, and deliberate skips live in
[`LANG_SPEC.md`](LANG_SPEC.md).
