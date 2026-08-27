# AGENT HANDOFF v2 — language-coding-standards

Last updated: **2026-08-27**

Repository: `StevenBuglione/language-coding-standards`

Reviewed baseline: `de8e0bc6a99fe5c3b3cc94b33b22abc58fa4fa96`

Remediated code baseline before this documentation commit:
`9c73af96a3530e6d9750cd57ba0a725b42ccad4a`

## 1. Executive decision

This repository is substantially stronger than the audited baseline, but it is
**not yet the definitive reference for every language**. Keep all eight packs
in `experimental` state until the acceptance criteria in this handoff are met.

The audit's main finding was not “the code is generally bad.” The main finding
was that several green capabilities proved less than their names promised, and
root metadata had drifted far behind the implementation. Those false-green and
status-integrity defects were corrected directly on `main`.

Do not undo the fixes by lowering thresholds, broadening test selectors,
reintroducing compile-only package checks, or turning unsupported capabilities
into cosmetic passes.

## 2. Corrections completed

### Repository-level integrity

- `scripts/manifest.py --check` now validates **every implemented pack**, not
  only candidate/reference packs.
- The manifest is checked against executable verifiers, canonical capability
  names, Dockerfile image references, workflow image inputs, and compose
  services.
- Meta CI runs the on-disk manifest validation.
- The reusable container preamble now supports slim images where checkout uses
  GitHub's REST archive path and `git` is intentionally absent.
- README/status text now separates normative contracts, current evidence, and
  historical audit snapshots.

### Go

- Removed `curl | sh`-style executable remote installation for
  `golangci-lint`.
- Downloads the immutable release archive and checksum manifest, validates the
  manifest against a committed SHA-256, validates the selected archive, then
  installs the binary.
- Named test capabilities parse `go test -json` and fail if zero tests execute.
- The package gate builds and executes the command and validates its output.
- Strict complexity findings were resolved through smaller helpers rather than
  relaxed linter limits.

### Java

- Bootstrap now verifies exact Java 25 and Maven 3.9.16 baselines.
- Named Surefire gates delete old reports, execute the selector, parse XML, and
  require a nonzero test count.
- The package gate installs the JAR, verifies expected contents, and compiles
  and executes a clean consumer with `javac`.
- The official Maven image's inherited `MAVEN_CONFIG` is cleared before invoking
  the checksum-pinned wrapper.
- PMD 7 configuration no longer references the removed dataflow rule or leaves
  `LoosePackageCoupling` silently misconfigured; package direction remains an
  ArchUnit responsibility.

### Python

- All project tools run with `uv run --locked` where supported.
- Bootstrap checks exact CPython 3.13 and uv 0.12.6 baselines.
- Every scoped pytest capability performs a collection proof and requires a
  nonzero singular or plural count.
- Coverage and conformance now receive the same zero-test protection.
- `uv build` is preceded by `uv lock --check`, and the package gate rejects any
  change to `uv.lock` because pinned uv 0.12.6 has no `uv build --locked` flag.
- Coverage was recalibrated honestly from the measured 91.75% branch baseline
  using the repository's “measured minus four, floor 85” rule: 87%, not the
  unsupported 96% claim.
- The conformance adapter now executes all money, quantity, SKU, and order v2
  vectors using typed, parameterized handlers rather than a partial branch-heavy
  test.

### Rust

- The property capability runs the actual `money_properties` and
  `order_properties` integration-test targets instead of doctests.
- `cargo nextest` receives `--no-tests=fail` for scoped proof gates.
- The package gate removed `--no-verify`; Cargo now extracts and builds from the
  packaged contents.
- Coverage also fails when no tests execute.

### TypeScript

- Added a real build configuration that emits CommonJS JavaScript, declarations,
  source maps, and package-local module metadata into `dist`.
- Package metadata declares a public entry point and ships only `dist`.
- The package gate creates a tarball, verifies mandatory files, rejects leaked
  `src`, installs the tarball into a clean consumer, type-checks the consumer,
  and executes it.

### Swift

- Every filtered Swift test capability routes through one zero-test detector.
- The detector accepts Swift Testing's singular `1 test` and plural forms while
  rejecting the separate XCTest `Executed 0 tests` summary.
- The full-tier AddressSanitizer run uses the same proof.

### C# and Kotlin

- No risky version churn was applied during the proof-integrity remediation.
  Their current implementations were audited and their real capabilities are
  now represented accurately in the manifest and current-status document.
- Their version migrations remain explicit, ranked follow-up work below.

## 3. Research conclusions that govern the next changes

Use primary project documentation when refreshing this section.

### Go

Go 1.27 was released on 2026-08-19. The repository may keep Go 1.26 as an
explicit compatibility floor, but specs must not call it the current release.
Modern Go supports `tool` directives in `go.mod`; do not repeat the obsolete
claim that tracked developer tools require only a `tools.go` blank-import
workaround.

Primary sources:

- https://go.dev/blog/go1.27
- https://go.dev/doc/modules/managing-dependencies#tools

### Java

JDK 25 is the correct LTS baseline. Java 26 is non-LTS and is superseded on the
six-month feature cadence. Keep exact-version evidence unless the repository
intentionally adds a multi-JDK compatibility matrix.

Primary source:

- https://www.oracle.com/java/technologies/java-se-support-roadmap.html

### Python

Python 3.14.7 is the current feature-series maintenance release. Python 3.13 is
still a legitimate supported compatibility floor. Describe it as the oldest
supported/tested baseline, not “the current stable line.” Add a 3.14 lane before
changing the minimum unless project policy explicitly drops 3.13.

Primary sources:

- https://www.python.org/downloads/release/python-3147/
- https://devguide.python.org/versions/

### Rust

Rust 1.98 is current for this audit. Keep the extracted-package verification;
Cargo's `--no-verify` explicitly skips the clean package build and is not valid
for a package proof.

Primary sources:

- https://doc.rust-lang.org/stable/releases.html
- https://doc.rust-lang.org/cargo/commands/cargo-package.html

### TypeScript

TypeScript 6 and Node 24 are coherent for this pack. Package evidence must
continue to exercise emitted contents. A `tsconfig` with `noEmit: true` plus
`pnpm pack` is never sufficient evidence for a distributable library.

Primary source:

- https://www.typescriptlang.org/docs/handbook/release-notes/typescript-6-0.html

### C#

.NET 9 is STS and reaches end of support on **2026-11-10**. .NET 10 is active
LTS through **2028-11-14**. Migrate the pack to .NET 10 before doing lower-value
cleanup, and regenerate lock files under the new SDK rather than hand-editing
them.

Primary source:

- https://dotnet.microsoft.com/platform/support/policy

### Kotlin

Kotlin 2.4.10 is the current stable release and the 2.4 line has an explicit
support window. The pack remains on 2.2.10. Upgrade Kotlin and its compatible
Gradle/plugin matrix as one tested change. Keep detekt 1.23.8 until detekt 2 is
stable unless the repository deliberately accepts alpha tooling.

Primary sources:

- https://kotlinlang.org/docs/releases.html
- https://github.com/detekt/detekt/releases

### Swift

Swift 6.3 is the current released language line. The Swift 6.0 pack should be
migrated and rebaselined on Linux, but version movement alone will not close its
larger evidence gaps: lint, coverage, dependency security/policy, and mutation.

Primary source:

- https://www.swift.org/blog/swift-6.3-released/

## 4. Ranked remaining work

### P0 — protect the evidence

#### P0.1 Protect `main`

The branch is currently unprotected. Configure a ruleset or branch protection
that requires pull requests, blocks force pushes/deletion, dismisses stale
approvals as appropriate, and requires the meta plus affected language checks.

Acceptance criteria:

- GitHub reports branch protection/ruleset enforcement on `main`.
- A pull request cannot merge while a required language or meta check fails.
- Administrators do not have a routine bypass path that makes the policy
  cosmetic.

#### P0.2 Pin every container image by digest

GitHub actions are full-SHA pinned, but language and meta containers still use
mutable tags and manifest `digest` values are `null`.

Acceptance criteria:

- Every workflow and Dockerfile uses a reviewed immutable digest.
- The manifest records the same digest and validates it.
- Renovation is automated through reviewable pull requests.
- A negative manifest test proves a tag/digest mismatch fails meta CI.

#### P0.3 Complete shared conformance

Go, Java, Rust, and TypeScript still report `conformance` unsupported.

Acceptance criteria:

- Each adapter enumerates the catalog's required IDs and fails for missing,
  duplicate, or ignored vectors.
- Every money, quantity, SKU, order, and workflow vector executes against
  production APIs.
- A negative fixture changes one expected result and proves the adapter fails.
- `conformance` becomes a required capability for all eight packs.

### P1 — supported platforms and security coverage

#### P1.1 Migrate C# to .NET 10 LTS

Update SDK image, `global.json`, target frameworks, package compatibility,
lockfiles, workflow, manifest, and spec in one commit. Run all three CI jobs and
clean NuGet consumer evidence before merging.

#### P1.2 Upgrade Kotlin and Swift

- Kotlin: migrate 2.2.10 to stable 2.4.x with a compatible Gradle/plugin matrix.
- Swift: migrate 6.0 to stable 6.3.x on Linux.

Do not combine these migrations with unrelated rule suppression.

#### P1.3 Add missing vulnerability/policy gates

- Java: pinned advisory scanner covering runtime and build/test dependencies.
- Kotlin: pinned advisory scanner with a reproducible vulnerability database or
  service contract.
- Swift: dependency advisory and license/source policy.
- TypeScript: a dedicated local SAST capability or a documented root policy
  that makes repository CodeQL authoritative.

Every scanner needs a stable negative fixture or test repository proving it
fails closed. An unavailable vulnerability service must fail or emit an
explicit unsupported/error state; it must not silently pass.

#### P1.4 Implement reproducibility evidence

Every pack currently treats two-clean-build comparison as root evidence, but no
root reproducibility job proves it.

Acceptance criteria:

- Two clean workspaces build the same distributable.
- Known nondeterminism is normalized narrowly and documented.
- The compared artifact is the same one the package consumer installs.
- Differences produce inspectable diagnostics and fail CI.

#### P1.5 Actually schedule the full tier

Mutation configuration that never runs is not evidence. Add a scheduled full
workflow with timeouts, retained reports, and committed thresholds. Go and
Swift must remain explicitly unsupported until a trustworthy mutator exists;
do not fake a score with hand-written source replacement.

### P2 — clarity and maintenance

- Add Go 1.27 and Python 3.14 compatibility lanes while retaining declared
  floors until policy changes.
- Replace tag-only tool bootstrap wherever an upstream checksum/signature is
  available.
- Add tests that delete or rename one required test and prove each scoped gate
  rejects zero execution.
- Generate the human-readable capability matrix from the manifest and verifier
  output so it cannot drift.
- Review `LANG_SPEC.md` files after every toolchain migration; version language
  must distinguish “compatibility floor,” “current tested line,” and “latest
  upstream release.”

## 5. Non-negotiable implementation rules

1. Never lower a quality, coverage, or mutation threshold merely to make CI
   green. Re-measure and document the formula when a baseline legitimately
   changes.
2. Never use `SKIP_UNSUPPORTED` to hide a tool installation or configuration
   failure.
3. Never report a test capability as pass without proving a nonzero test count.
4. Never report a package capability as pass without installing/consuming only
   packaged contents in a clean environment.
5. Never call an unused-dependency detector a dead-code detector.
6. Never call a dependency audit SAST.
7. Never execute downloaded shell scripts directly. Verify immutable artifacts
   or compile checksum-verified modules at pinned versions.
8. Keep production architecture rules structural and future-proof; do not
   hard-code today's file list so new files bypass enforcement.
9. Keep historical evidence immutable and clearly labeled with its baseline
   SHA.
10. Make one coherent change per commit and inspect the affected GitHub Actions
    logs before advancing.

## 6. Verification procedure for the next agent

Run these before changing anything:

```bash
python3 scripts/manifest.py --check
python3 -m unittest discover -s scripts/tests
python3 conformance/v2/validate.py
python3 -m unittest discover -s conformance/v2/tests
python3 scripts/manifest.py --list
```

For a language change:

```bash
cd <language>
./verify.sh bootstrap
./verify.sh <affected-capability>
./verify.sh
```

Then inspect all GitHub check runs on the pushed commit. A successful local
command is not enough when the canonical environment is the workflow's
container.

Before promotion, run the full root set, every opted-out language workflow, the
scheduled full tier, reproducibility, and conformance. Record exact commit SHAs
and exact check conclusions in `docs/CURRENT_STATUS.md`.

## 7. Definition of done for “definitive standard”

The repository may claim a language pack is definitive only when:

- its state is promoted through review rather than edited ad hoc;
- all required capabilities fail closed and have negative evidence;
- the full shared contract passes;
- package, security, architecture, coverage, mutation, and reproducibility
  evidence are real;
- upstream versions are supported and accurately described;
- all mutable execution dependencies are pinned;
- `main` enforces the checks; and
- a clean clone can reproduce the documented result without hidden host state.

Until then, the honest label is **experimental, strong evidence in the listed
areas, explicit gaps elsewhere**.
