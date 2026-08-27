# Current implementation status

Last reviewed: **2026-08-27**

Audit baseline: `de8e0bc6a99fe5c3b3cc94b33b22abc58fa4fa96`

Remediated code baseline before this status-only commit:
`9c73af96a3530e6d9750cd57ba0a725b42ccad4a`

All packs remain **experimental**. Do not change a language to `candidate` or
`reference` merely because its current GitHub Actions run is green. Promotion
requires every required capability to have real evidence, shared conformance
to pass, image and action references to be immutable, and the root branch to
require those checks.

## Matrix

| Language | In default set | Declared baseline | Strongest evidence now present | Important open gaps |
| --- | ---: | --- | --- | --- |
| Go | yes | Go 1.26 compatibility baseline | checksum-verified lint bootstrap, race tests, zero-test detection, checked executable smoke test, coverage, gosec, govulncheck | shared conformance adapter, reproducibility, stable mutation evidence, image digest; review migration to Go 1.27 |
| Java | yes | JDK 25 + Maven 3.9.16 | exact toolchain check, zero-test-proof Surefire selectors, ArchUnit, PMD/Checkstyle/SpotBugs, installed-JAR clean consumer | shared conformance adapter, dependency advisory scanner, true dead-code detector, reproducibility, image digest |
| Python | yes | CPython 3.13 compatibility baseline + uv 0.12.6 | lock-preserving execution/build, strict typing/lint/architecture, Hypothesis, full v2 vector adapter, clean-wheel consumer, audited lock export | dependency license/source policy, reproducibility, image digest; add Python 3.14 compatibility coverage without silently dropping 3.13 |
| Rust | yes | Rust 1.98.0 | actual proptest integration targets, nextest zero-test failure, extracted-crate package verification, llvm-cov, cargo-deny | shared conformance adapter, public-API-aware dead-code proof, reproducibility, image digest |
| TypeScript | yes | Node 24 + pnpm 11.24.0 + TypeScript 6.0.2 | strict type check, dependency-cruiser, Vitest/fast-check, coverage, real `dist` tarball installed/type-checked/executed by a clean consumer | shared conformance adapter, dedicated local SAST capability, reproducibility, image digest |
| C# | no | .NET 9 compatibility baseline | locked restore, analyzers, architecture tests, generative tests, NuGet consumer, conformance adapter | migrate to .NET 10 LTS before .NET 9 support ends; dead-code, dependency policy, reproducibility, mutation, image digest |
| Kotlin | no | Kotlin 2.2.10 + Gradle 8.14.3 + JDK 21 | wrapper validation, detekt/ktlint, ArchUnit, Kotest property tests, distribution execution, conformance adapter | upgrade and rebaseline on Kotlin 2.4.x, dependency advisory scanner, dead-code, reproducibility, mutation, image digest |
| Swift | no | Swift 6.0 Linux compatibility baseline | strict test-count detection, filtered unit/property/integration/conformance tests, clean SwiftPM consumer | move to current Swift 6.3.x, pinned formatter/linter, coverage floor, dead-code, SAST, dependency security/policy, mutation, reproducibility, image digest |

## Evidence interpretation

`PASS` means the corresponding implementation actually ran and met its
committed threshold. The audit specifically corrected cases where a command
could pass while proving less than its capability name promised:

- Rust property tests now run the real `proptest` integration targets.
- Rust packaging no longer skips Cargo's extracted-package verification.
- Swift filtered tests fail when zero tests run.
- Go, Java, and Python named test scopes fail when zero tests are discovered.
- TypeScript packages emitted JavaScript and declarations, install into a clean
  consumer, type-check, and execute.
- Java packages install into the local repository and compile/execute a clean
  `javac` consumer.
- Go builds and executes its command artifact.
- Python validates the lock before build, rejects build-time lock mutation,
  installs the wheel into a clean virtual environment, and imports it.

## Historical conformance snapshot

`conformance/v2/gaps.json` is retained as immutable audit history for its
recorded baseline SHA. It must not be updated to look current. Current support
is declared by each pack's `requiredCapabilities` and demonstrated by its
`verify.sh` output. Python, C#, Kotlin, and Swift currently expose a conformance
capability; Go, Java, Rust, and TypeScript still report it as unsupported.

## Promotion rule

A pack may move from `experimental` only after all of the following are true:

1. Every capability required by the manifest either passes or has a root-level
   policy proving it is genuinely inapplicable.
2. Zero-test deletion/rename fixtures prove each scoped test gate fails closed.
3. The complete v2 conformance catalog is executed by the language adapter.
4. The package gate installs and exercises only packaged contents in a clean
   consumer.
5. Dependency vulnerability and policy coverage includes build/test tooling as
   well as runtime dependencies.
6. A clean-build reproducibility comparison is implemented and scheduled.
7. Container images use immutable digests and GitHub actions remain full-SHA
   pinned.
8. `main` is protected and requires the relevant checks.
9. The full/nightly tier actually schedules mutation and other expensive gates;
   a configured but never-run tool is not evidence.
