# Swift language specification

This pack is an **experimental** implementation of [`docs/CONTRACTS.md`](../docs/CONTRACTS.md)
v2 for Swift. Silence here means compliance; every skip and platform limit is
named.

## Platform honesty

**Evidence is Linux-only.** CI and the local image are `swift:6.0` (official
Ubuntu-based toolchain). A green Linux run does **not** prove Darwin, iOS,
tvOS, watchOS, or Xcode behavior. Apple platforms are unproven: no macOS
workflow, no simulator job, no Apple SDK pin. Do not claim SwiftUI, Combine,
or Apple-only APIs from this pack.

The Dockerfile is `FROM swift:6.0` with no digest yet (ADR-007: tags are
names; digest pinning is WP3). `inDefault` is `false` so this pack does not
enter default `verify-all` or Compose until a maintainer opts in.

## Toolchain

| Concern | Tool | Pin | Why | Source |
| --- | --- | --- | --- | --- |
| Compiler | Swift 6.0 / SwiftPM | image tag `swift:6.0`; `// swift-tools-version: 6.0` | the image tag **is** the toolchain | <https://hub.docker.com/_/swift>, <https://www.swift.org/install/> |
| Format | bundled `swift format` | toolchain | check-only `lint --strict`; repository style, not an official Swift mandate | <https://github.com/swiftlang/swift-format> |
| Tests | Swift Testing | toolchain | `@Test` / `#expect` on Linux; XCTest remains available | <https://developer.apple.com/xcode/swift-testing/> |
| Package | `swift build -c release` | toolchain | release library artifact; consumer fixture not yet wired | <https://docs.swift.org/swiftpm/> |

Quality tools that are not part of the official image are **not** baked in.
`bootstrap` is `swift package resolve` against this zero-dependency package.

## Gate-by-gate

`./verify.sh` prints one `GATE <capability>: …` line per requested capability
and exits nonzero on the first `FAIL`. Experimental skips are `SKIP_UNSUPPORTED`.

| Capability | Implementation | Notes |
| --- | --- | --- |
| `bootstrap` | `swift package resolve` | Proves the toolchain can resolve the package. |
| `format` | `swift format lint --strict --recursive Sources Tests Package.swift` | `SKIP_UNSUPPORTED` when `swift format` is absent. |
| `lint` | skip | No SwiftLint pin in this pack. |
| `compile` | `swift build --build-tests` | Production and tests type-check. |
| `architecture` | skip | Single library target; import-graph rules not generated. |
| `unit` | `swift test` | Zero executed tests is `FAIL`. Place-order adapter tests run here. |
| `property` | skip | No generative framework wired. |
| `integration` | skip | Place-order tests currently live under `unit`. |
| `package` | `swift build -c release` plus an artifact smoke | Looks for `Warehouse.swiftmodule` / `libWarehouse.*`. |
| `coverage` | skip | `swift test --enable-code-coverage` floors not parsed. |
| `dead-code` | skip | No unreachable-declaration detector. |
| `sast` | skip | No source-level scanner. |
| `dependency-vulnerability` | skip | No advisory source wired. |
| `dependency-policy` | skip | No license/source policy tool. |
| `lock-integrity` | skip | No third-party pins yet. |
| `negative-fixtures` | `bad_examples/assert.sh` | Compile fixture always; format fixture when the tool exists. |
| `mutation` | skip | No trustworthy Swift mutator; do not simulate one. |
| `conformance` | skip | Shared JSON vectors not wired (WP4). |
| `reproducibility` | skip | Two-clean-build comparison is WP7 root evidence. |

## Domain mapping

Canonical warehouse-order v2 lives in `Sources/Warehouse`:

- `Money`, `Quantity`, `Sku`, `Order` with an injected `OrderId`
- `PlaceOrderUseCase`: validate, `reserveAll`, charge, mark **PAID**, persist
- Charge decline releases the reservation
- Save failure refunds and releases
- Compensation failure is a distinct `CompensationFailure`
- In-memory adapters are serial-queue guarded

Deviations called out:

- Swift `Bool` is not a subtype of `Int`, so Python's explicit `bool`
  rejection for `Quantity` is unrepresentable and not tested as a runtime
  case.
- `Order` is a value type; `snapshot()` is a copy by construction.
- Integer overflow uses `addingReportingOverflow` /
  `multipliedReportingOverflow` so overflow is `InvalidOrder`, never trap.
- Currency is ISO-style `^[A-Z]{3}$`; `ZZZ` is valid. This is not ISO-4217
  membership.

## Negative fixtures

| fixture | gate | signal |
| --- | --- | --- |
| `type_violation` | compile | `cannot convert value of type 'String'` |
| `unformatted` | format | `swift format lint --strict` nonzero when the tool exists |

Fixtures sit outside `Sources/` and `Tests/` so the main package never
compiles them.

## Local run

```bash
docker run --rm -v "${PWD}/swift:/workspace" -w /workspace swift:6.0 bash ./verify.sh
```

There is no Compose service yet (`inDefault: false`). Apple hosts are not a
supported evidence path for this pack.
