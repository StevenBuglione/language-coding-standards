# C# language specification (experimental)

This pack implements [`docs/CONTRACTS.md`](../docs/CONTRACTS.md) domain v2 for
C# / .NET 9. Silence here means compliance; deviations and
`SKIP_UNSUPPORTED` capabilities are called out explicitly.

## Philosophy

CI is the style guide. For a coding agent working in C# the definition of
"done" is `./verify.sh` printing one `GATE <capability>: PASS` (or an honest
`SKIP_UNSUPPORTED`) line per requested capability.

## Toolchain

| Concern | Tool | Pin | Why |
| --- | --- | --- | --- |
| SDK | .NET 9 | `global.json` `9.0.100` + `rollForward: latestFeature` | Stay on the 9.0 feature band; the `mcr.microsoft.com/dotnet/sdk:9.0` image supplies the patch. `disable` would break on patch-tag drift. |
| Policy | `Directory.Build.props` | nullable, `TreatWarningsAsErrors`, `AnalysisMode` All, `EnableNETAnalyzers`, `EnforceCodeStyleInBuild` | Warnings never survive as warnings. |
| Versions | `Directory.Packages.props` | Central Package Management | One pin list. |
| Restore | `packages.lock.json` + `dotnet restore --locked-mode` | Per-project lockfiles | Offline/frozen resolution after bootstrap. |
| Format | `dotnet format --verify-no-changes` | SDK-shipped | Never rewrites in CI. |
| Tests | xUnit 2.9.x | CPM pin | Separate unit / property / integration projects; zero tests is a failure. |
| Package | `dotnet pack` + consumer smoke | `Warehouse.Domain` nupkg | Installs the packed library from a clean fixture. |

`rollForward: latestFeature` (not `disable`) is documented here because the
Dockerfile uses the floating `9.0` tag. A later candidate-grade pin should
record the image digest (ADR-007) and may then use `disable` against that
exact SDK.

## Gate-by-gate

| Capability | Command / status |
| --- | --- |
| bootstrap | `dotnet restore --locked-mode` when lockfiles exist |
| format | `dotnet format Warehouse.sln --verify-no-changes` |
| lint | `SKIP_UNSUPPORTED` — style analyzers already run during compile |
| compile | `dotnet build --no-restore -c Release -warnaserror` |
| architecture | xUnit reflection tests: domain ↛ application/adapters; application ↛ adapters |
| unit / property / integration | `dotnet test` on the matching project; zero executed tests fail the gate |
| package | pack Domain, restore+run a temp consumer against the nupkg |
| coverage | coverlet.msbuild line floor 70 on unit tests (VSTest). MTP `Microsoft.Testing.Extensions.CodeCoverage` requires xUnit v3; this pack stays on xUnit 2.9 + coverlet until that migration. |
| dead-code | `SKIP_UNSUPPORTED` — IDE0005 runs in compile; no reachability scanner |
| sast | same Roslyn analyzer build as compile (`AnalysisMode` All) |
| dependency-vulnerability | `dotnet list package --vulnerable --include-transitive` |
| dependency-policy | `SKIP_UNSUPPORTED` — no license/unused-deps tool yet |
| lock-integrity | `dotnet restore --locked-mode` |
| negative-fixtures | `bad_examples/assert.sh` |
| mutation | `SKIP_UNSUPPORTED` — Stryker.NET is maintained; not fixture-proven in this pack |
| conformance | xUnit loads `conformance/v2/suites` (money, quantity, sku, order) |
| reproducibility | `SKIP_UNSUPPORTED` — WP7 root evidence |

Property tests are seeded generative xUnit theories, not FsCheck. FsCheck
remains the candidate-grade path once reviewed.

`NoWarn` currently includes `CA1515` (public library types), `CA1014`
(CLSCompliant), `CA1032` (standard exception constructors; domain errors are
payloads), `CS1591` (XML docs are not the style guide), `CA1034` (nested
result records), `CA1716` (`Get`/`Next` match CONTRACTS.md), and `CA1859`
(keep abstract result types). Revisit before candidate promotion.

## Domain notes

- Money stores `long` minor units, ISO-style `^[A-Z]{3}$` (including `ZZZ`),
  inclusive max `9007199254740991`, checked overflow → `InvalidOrderException`.
- Quantity is `int` in `1..=2147483647`; the upper bound is the type itself.
- SKU strips only ASCII space/tab/CR/LF; UTF-8 length `1..=64`.
- Order IDs are injected. Legal transitions: `New → Paid → Shipped`.
- `PlaceOrderUseCase` validate → `reserveAll` → charge (idempotency key) →
  `pay()` → save; decline releases stock; save failure refunds and releases.
  Compensation failure is a typed `CompensationFailure`.
- Repository snapshots never alias stored state.

## Negative fixtures

`bad_examples/` is not in `Warehouse.sln`. `assert.sh` maps:

- `unformatted` → format (`dotnet format --verify-no-changes`)
- `compile_fail` → compile (`CS0029`)
