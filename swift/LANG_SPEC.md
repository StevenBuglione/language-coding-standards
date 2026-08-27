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
| Warnings | `-warnings-as-errors` via `unsafeFlags` | Swift 6.0 | `treatAllWarnings(as: .error)` is SwiftPM 6.2+ (SE-0480); 6.0 uses the same compiler flag | <https://github.com/swiftlang/swift-evolution/blob/main/proposals/0480-swiftpm-warning-control.md> |
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
| `architecture` | source scan of `Sources/Warehouse/Domain` | Domain files must not mention application/adapter types. |
| `unit` | `swift test --filter` domain + conformance + property | Zero executed tests is `FAIL`. |
| `property` | seeded Money commutativity tests | No third-party generator. |
| `integration` | `swift test --filter PlaceOrderTests` | Adapter-wired place-order. |
| `package` | `swift build -c release` plus a path-dependent consumer package | Consumer depends on the directory name (SwiftPM path-id), not `Package.swift`'s `name`. |
| `coverage` | skip | `swift test --enable-code-coverage` floors not parsed. |
| `dead-code` | skip | No unreachable-declaration detector. |
| `sast` | skip | CodeQL is GitHub-hosted SAST, not in `swift:6.0`. Linux ASan is `VERIFY_TIER=full` (`GATE sanitizers`), not this capability. LeakSanitizer is off: the Swift/XCTest runtime leaks ~144B on this image. |
| `dependency-vulnerability` | skip | No advisory source wired. |
| `dependency-policy` | skip | No license/source policy tool. |
| `lock-integrity` | `Package.resolved` present | Zero third-party pins; the file is the fingerprint. |
| `negative-fixtures` | `bad_examples/assert.sh` | Compile fixture always; format fixture when the tool exists. |
| `mutation` | skip | No trustworthy Swift mutator; do not simulate one. ASan is not mutation. |
| `conformance` | Swift Testing loads `conformance/v2/suites` | Money, quantity, SKU, order. |
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
