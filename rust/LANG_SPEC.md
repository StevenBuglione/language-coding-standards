# Rust language specification

This template is a reference implementation of [`docs/CONTRACTS.md`](../docs/CONTRACTS.md)
for Rust, alongside the Python, TypeScript, and Go templates. Every knob lives
in the root [`Cargo.toml`](Cargo.toml) (`[workspace.lints]`),
[`clippy.toml`](clippy.toml), [`deny.toml`](deny.toml),
[`verify.sh`](verify.sh), and the [`Dockerfile`](Dockerfile); this document
explains why each knob sits where it does, what it forbids, and where we
deliberately chose not to enforce. Silence here means compliance with the
contract; deviations are called out explicitly.

## Philosophy

CI is the style guide ([`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md)). For a
coding agent working in Rust the consequence is sharper than anywhere else,
because Rust's own culture already says "make illegal states unrepresentable":
the gates just refuse to let the culture stay aspirational.

- strictness becomes a lint roster where every `warn` is promoted to a build
  failure, not "we follow API guidelines";
- architecture becomes the workspace crate graph itself — the compiler is the
  boundary guard;
- honest tests become a coverage floor fused with nextest plus property tests
  that shrink real counterexamples;
- trust in the gates themselves becomes `bad_examples/`, fixtures each gate
  must reject on demand.

Rust-specific reality shapes some choices: there **is** a compiler, and an
unusually expressive one, so more contracts than any other language here are
pushed into types (`Quantity` cannot be zero; `Money` cannot be negative)
instead of linters. What the compiler cannot express — style, pedantry,
complexity, supply chain — becomes clippy, cargo-deny, and cargo-shear.

## Toolchain

| Concern | Tool | Pin | Why | Source |
| --- | --- | --- | --- | --- |
| Compiler | stable rustc | `1.98.0` exact in `rust-toolchain.toml`; image tag `rust:1.98.0-bookworm`; MSRV `1.85` in `[workspace.package]`, mirrored by `msrv` in `clippy.toml` | exact-patch pin on both sides means rustup resolves to the preinstalled toolchain and downloads nothing | <https://doc.rust-lang.org/cargo/reference/rust-toolchain.html>, <https://hub.docker.com/_/rust> |
| Format | stable rustfmt | `cargo fmt --all --check` from the pinned toolchain | check-only; nightly-only options deliberately deferred (see Deliberate non-enforcements) | <https://github.com/rust-lang/rustfmt> |
| Lint | clippy | toolchain-pinned; roster in `[workspace.lints]`, ceilings in `clippy.toml` | warnings are errors via `-D warnings` + `CARGO_BUILD_WARNINGS=deny`; roster below | <https://doc.rust-lang.org/clippy/lints.html>, <https://doc.rust-lang.org/clippy/configuration.html> |
| Types | `cargo check --all-targets --locked` | toolchain-pinned | the compiler IS the typechecker; the phase stays independent of clippy so neither can masquerade as the other | <https://doc.rust-lang.org/cargo/commands/cargo-check.html> |
| Architecture | `cargo tree -e normal` edge assertions in verify.sh | toolchain-pinned | the workspace crate graph IS the architecture; see Gate-by-gate walkthrough | <https://doc.rust-lang.org/cargo/commands/cargo-tree.html> |
| Tests | built-in `#[test]` under nextest | cargo-nextest `0.9.143` | faster scheduling, per-test isolation, machine-readable output; retries stay 0 | <https://nexte.st/docs/> |
| Coverage | cargo-llvm-cov fused with nextest | cargo-llvm-cov `0.9.0`; llvm-tools-preview added by deps phase | native `--fail-under-lines` floor flag; same runner as the test gate | <https://github.com/taiki-e/cargo-llvm-cov> |
| Property | proptest | `1.11.0` (dev-dep of domain) | shrinking counterexamples beat table-driven sampling; two required properties live in `crates/domain/tests/` | <https://proptest-rs.github.io/proptest/> |
| Complexity | clippy `too_many_lines` + argument/error-size ceilings | clippy.toml thresholds | see Thresholds and Deliberate non-enforcements (inert cognitive_complexity swap) | <https://rust-lang.github.io/rust-clippy/master/index.html#/too_many_lines> |
| Dead code | rustc `dead_code` (in lint) + cargo-shear (this gate) | cargo-shear `1.13.4` | unused CODE is a compile-time warning already fatal under deny-warnings; unused DEPENDENCIES need their own oracle | <https://github.com/Boshen/cargo-shear> |
| Security | cargo-deny | `0.20.2` | advisories (RustSec) + license allowlist + duplicate/wildcard bans + source allowlist in one gate | <https://embarkstudios.github.io/cargo-deny/> |
| Deps hygiene | committed Cargo.lock + `--locked` everywhere; freshness via `cargo metadata --locked` | toolchain-pinned | resolution under `--locked` succeeds only when the lockfile exactly matches the manifests | <https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html> |
| Mutation | cargo-mutants, config at `.cargo/mutants.toml` | `27.1.0` (installed lazily, nightly tier only) | UNSCHEDULED roadmap: economics below | <https://mutants.rs/> |

### Why `unsafe_code = "forbid"`, not "deny"

`deny` can be re-allowed locally by an `#[allow(unsafe_code)]` attribute —
one quiet line reopens the entire surface. `forbid` cannot be overridden by
any inner attribute, so unsafe code becomes a *compile error* rather than a
policy violation someone may talk themselves into suppressing. The one cost
is rigidity: a genuinely necessary `unsafe` block requires editing the
workspace manifest, which is precisely the review event such code deserves.
The fixture proving this bites is `bad_examples/unsafe_block/`, which carries
the forbid in its own manifest and fails plain `cargo check`.

### Why `[workspace.lints]` instead of per-crate configuration

Cargo's lint-table inheritance ([the-lints-section](https://doc.rust-lang.org/cargo/reference/manifest.html#the-lints-section))
lets members declare `[lints] workspace = true` and receive the entire roster
from the root manifest. Centralization matters mechanically, not aesthetically:

- there is exactly one place where "warnings are errors" is negotiated; a new
  crate inherits strictness before its first line compiles;
- drift between crates is impossible, whereas four hand-copied `[lints]`
  tables drift the first time someone adds a lint to one of them;
- the bad_examples probes can quote the SAME roster as explicit flags,
  so fixtures test the rules production enforces, not a copy of them.

### Install strategy and supply-chain tradeoff

Nothing quality-related is baked into the image (CONTRACTS §6). All four
tools install during `deps` through `cargo install --locked <crate>@<exact
version>` into `$CARGO_HOME/bin` (workspace-relative, gitignored). This is
slower than prebuilt-binary installers — each tool compiles from source on a
cold cache, minutes in total — but every byte arrives through the
checksum-verified crates.io index under a lockfile, with zero extra trust
anchors (no installer scripts, no release-CDN TLS). We considered
`taiki-e/install-action`-style binary downloads with manual checksum files;
that trades compile time for a second supply chain we would have to audit.
For a template whose whole point is auditable pins, source builds win.
Repeat runs pay nothing: `cargo install` no-ops when the exact version is
already installed, and `.cargo-home` persists across local runs.

### Why the compiler is pinned twice (toolchain file AND image tag)

`rust-toolchain.toml` names the channel for anyone building outside Docker.
Inside the container the image tag must agree, or rustup will silently
download a second toolchain — Go-template-style hermeticity demands that
never happen. Both name `1.98.0`; bump them together. A mismatch fails
closed (offline) rather than open.

## Gate-by-gate walkthrough

`./verify.sh` runs these phases in canonical order, printing one
`GATE <phase>: PASS` line each. Each phase names its proving fixture in
[`bad_examples/`](bad_examples/) where one exists.

1. **deps** — `cargo fetch --locked`, then pinned installs of
   cargo-nextest, cargo-llvm-cov, cargo-deny, cargo-shear, and
   `rustup component add llvm-tools-preview`. Every step fails explicitly;
   a half-installed toolchain must never surface later as a
   missing-command error in an unrelated gate.
2. **format** — `cargo fmt --all --check`. Check-only, never rewrite.
   Workspace-scoped by construction: `bad_examples/` is excluded from the
   workspace root, so rustfmt cannot see it. Fixture:
   `bad_examples/unformatted/` — `Diff in` and nonzero exit.
3. **lint** — `CARGO_BUILD_WARNINGS=deny cargo clippy --all-targets --locked
   -- -D warnings`. Warnings are errors
   twice over: rustc-level (`-D warnings`) and cargo-level
   (`CARGO_BUILD_WARNINGS=deny`, stabilized in Cargo 1.97, which errors when
   any crate emits lint warnings WITHOUT invalidating build caches the way
   `RUSTFLAGS="-D warnings"` does — hence preferred on the pinned 1.98).
   Roster beyond defaults: rustc `missing_docs`,
   `missing_debug_implementations`, `unreachable_pub`, `rust_2018_idioms`;
   clippy `pedantic` with `missing_errors_doc`/`missing_panics_doc` named
   explicitly; restriction denies `unwrap_used`, `expect_used`, `panic`,
   `todo`, `unimplemented`, `unreachable`, `dbg_macro`, `print_stdout`,
   `print_stderr`, `indexing_slicing`, `as_conversions`,
   `allow_attributes_without_reason`; and the complexity ceiling
   `too_many_lines` (30 lines, clippy.toml). Fixtures: too_complex,
   unwrap_used, indexing_slicing, print_stdout, todo_macro.
4. **types** — `cargo check --all-targets --locked`. Deliberately redundant
   with clippy: keeps the canonical slot independent of any linter. Fixture:
   `bad_examples/unsafe_block/` — a hard compile error under the forbid it
   declares itself.
5. **arch** — `cargo tree -e normal` assertions over the real workspace:
   `warehouse-domain` must depend on NO sibling, `warehouse-application`
   never on `warehouse-adapters`. Rust has no ArchUnit equivalent and no
   import-linter; the dependency graph itself is the contract, queried by
   the same resolver the build uses, so nothing can drift between "what the
   tool sees" and "what compiles". Cycles are banned by cargo during
   resolution — they fail this query before any assertion. Dev-dependencies
   are excluded from the query because integration tests legitimately wire
   adapters inward (documented exception). Supporting fixture:
   `bad_examples/pub_api_leak/` proves the `unreachable_pub` backstop (the
   pub-by-default discipline that keeps layer edges meaningful) still bites.
6. **test** — `cargo nextest run --locked`. Unit tests co-located per crate,
   integration tests in `crates/application/tests/place_order.rs` (happy
   path plus every failure path through REAL adapter doubles), property
   tests in `crates/domain/tests/`. Retries are pinned to 0 in
   [`.config/nextest.toml`](.config/nextest.toml): a flaky test is a broken
   test, and retrying it in CI hides the bug it is trying to report.
7. **coverage** — `cargo llvm-cov nextest --locked --fail-under-lines
   $COVERAGE_FLOOR`. Fused with nextest so both gates run the identical
   runner; the floor is native llvm-cov, not parsed output. Floor rationale
   in Thresholds.
8. **deadcode** — `cargo shear`: unused dependencies fail the build. Unused
   CODE is handled earlier by the compiler's `dead_code` warnings, already
   fatal inside the lint gate — the contract's "unused code and unused
   dependency detection" maps onto two mechanisms, both enforced. Fixture:
   `bad_examples/dead_code/` ("never used" under `-D warnings`).
9. **security** — `cargo deny check advisories bans licenses sources`.
   Advisories come from the RustSec database (cached under `.cache/`),
   yanked releases are denied, licenses must match the permissive allowlist
   in `deny.toml`, duplicate dependency versions and wildcard requirements
   are denied, and only crates.io is an accepted registry. cargo-audit-style
   continuous scanning remains a scheduled-workflow roadmap item; the gate
   here already blocks vulnerable graphs at build time.
10. **deps-hygiene** — `cargo metadata --locked`: resolution succeeds only
    when the committed Cargo.lock is exactly what the manifests demand. An
    edited `Cargo.toml` without a regenerated lockfile fails immediately.
    Honest note: cargo has no dedicated `uv lock --check` equivalent; locked
    metadata resolution IS that check, and it uses the same resolver code
    path as every other command.
11. **negative** — `bash bad_examples/assert.sh` runs all nine fixtures
    scoped to their explicit manifests, asserting nonzero exits plus the
    expected stable signals (JSON lint codes for clippy — human formats do
    not render names stably).

The optional `mutation` phase prints `GATE mutation: SKIP (nightly tier
only)` unless `VERIFY_TIER=full`, in which case it lazily installs the
pinned mutator and floors the kill score (`MUTATION_FLOOR`, default 70).

## Thresholds

| Threshold | Value | Rationale | Trade-off |
| --- | --- | --- | --- |
| too-many-lines-threshold | 30 | function-size ceiling; the planned `cognitive_complexity` knob no longer emits on current clippy (its docs disclaim it as a measurement tool), so complexity is bounded through hard length — verified to bite via bad_examples/too_complex | a genuinely long match table needs splitting |
| too-many-arguments-threshold | 5 | past five parameters, callers stop reading; introduce a struct | mechanical churn when signatures grow |
| large-error-threshold | 128 | error values are returned constantly; oversized enums tax every Result | forces boxed/compact error designs early |
| coverage measured baseline | **95.77%** lines across the workspace (first green run; 615 instrumented, 26 missed) | reference point for R3 | see breakdown below |
| coverage floor | **91** (= measured − 4, rounded down, ≥ 80) | R3 buffer absorbs small refactors without licensing gaps | new branches need tests within ~4 points of landing |
| uncovered-by-construction | none material | every branch is reachable: transitions have tests for all three states, ports have shortage/decline doubles, arithmetic overflow paths use bounded property ranges; the ~4% residue is Display/error-format plumbing exercised only through message assertions | revisited if defensive code appears |
| nextest retries | 0 | flakes are failures; retrying hides the signal CI exists to send | a genuinely flaky environment fails visibly |
| multiple-versions (bans) | deny | duplicate transitive versions are where dependency hell starts | rare legitimate dupes need a reviewed skip entry |

## Deliberate non-enforcements and deviations

Every entry here is a decision, recorded so silence cannot be mistaken for
oversight.

- **No cross-crate arch_violation fixture — mapping change vs the brief.**
  Workspace lints and `cargo tree` queries cannot see into a foreign crate,
  so a standalone "application imports adapters" fixture would prove nothing:
  outside the workspace, NOTHING enforces layering, and the probe would
  assert the absence of enforcement. Instead the arch phase asserts the real
  workspace's edges (positive enforcement), and `bad_examples/pub_api_leak/`
  negatively proves the `unreachable_pub` discipline that keeps public
  surfaces honest. Documented in `bad_examples/README.md` as well.
- **Complexity ceiling is too_many_lines, not cognitive_complexity — brief
  deviation.** The plan called for `cognitive-complexity-threshold = 15`;
  on the pinned toolchain that lint provably never emits (verified with
  threshold 0 against deliberately deep nesting — clippy's own docs now
  disclaim it: "We used to think it measured how hard a method is to
  understand"). Shipping an inert knob would violate the negative-fixture
  contract, so the ceiling is `clippy::too_many_lines` at 30 lines, denied
  workspace-wide and proven to bite by bad_examples/too_complex. The
  bad_examples probe caught the dead lint immediately — exactly what the
  pattern is for.
- **Feature-gate matrix (cargo-hack each-feature): skipped at v0.** The
  template ships zero features across all three crates — there is no matrix
  to check. When the first feature lands, add cargo-hack to deps and an
  arch-adjacent step; recorded as roadmap, not silence.
- **trybuild compile-fail suite: roadmap.** Compile-fail testing (asserting
  that wrong code does NOT compile) would strengthen the negative story, but
  it needs its own fixture crates and UI-normalization machinery; v0 ships
  the cheaper, sufficient proof via bad_examples. Roadmap item.
- **Nightly rustfmt options: roadmap.** `imports_granularity`,
  `group_imports`, and friends are unstable-only; enabling them would couple
  the template to nightly rustfmt behavior that changes between releases.
  Stable stock formatting (max_width 100, rest default) until those options
  stabilize.
- **Mutation testing: configured-not-floored, UNSCHEDULED.**
  `.cargo/mutants.toml` excludes tests and bounds mutant runtime. Full-tier
  economics: ~150 mutants × clean-suite seconds × timeout multiplier puts a
  run in the tens-of-minutes range even for this tiny workspace — real but
  affordable nightly, pointless as a PR gate. The kill-score floor activates
  when the nightly tier schedules it (`VERIFY_TIER=full`); until then the
  phase skips loudly rather than pretending.
- **OrderId is a process-local counter, not a UUID.** Avoiding a uuid crate
  for one value object keeps the deliberate-dependency budget at thiserror +
  proptest(dev). Uniqueness holds within a process; cross-restart uniqueness
  belongs to whatever storage backs the repository. Documented on the type.
- **Adapters dev-dependency in application.** Integration tests wiring real
  doubles into the use case require `warehouse-adapters` under
  `[dev-dependencies]` of `crates/application`. Production dependency
  direction stays inward; the arch phase's `-e normal` query excludes dev
  edges, so the exception is visible and bounded to test targets.
- **deps-hygiene has no dedicated check subcommand.** `cargo metadata
  --locked` is the freshness oracle (see walkthrough). Vulnerability
  auditing intentionally lives in security via cargo-deny advisories —
  running two advisory databases would double the noise, not the safety.
- **Test-side unwrap/panic suppressions carry reasons.** Tests construct
  known-valid values and read errors; module-level
  `#![allow(clippy::unwrap_used, reason = "...")]` documents each. The
  reasons are the point: `allow_attributes_without_reason` makes bare
  suppression uncompilable anywhere in the workspace.

## Workflows

### Clone and go

1. Copy `rust/` wholesale into your repository.
2. Rename the crates: change `warehouse-*` package names under `crates/`,
   the `[workspace.dependencies]` entries, import paths, and the
   `-p warehouse-*` arguments in verify.sh's arch phase.
3. Keep `bad_examples/` paired with the `negative` phase; deleting one
   without the other removes the proof that your gates bite.
4. Bump the tool pins together in verify.sh (`NEXTEST_VERSION`,
   `LLVM_COV_VERSION`, `CARGO_DENY_VERSION`, `CARGO_SHEAR_VERSION`) — the
   exact pins are the supply-chain contract.
5. Re-measure coverage after your first green run and reset
   `COVERAGE_FLOOR` per the R3 rule; record the baseline in Thresholds.

### Hermetic run

```bash
docker compose build rust          # official rust:1.98.0-bookworm only
docker compose run --rm rust       # mounts ./rust at /workspace, runs verify.sh
docker compose run --rm rust lint  # any subset of phases, canonical order
```

Caches (`CARGO_HOME`, `CARGO_TARGET_DIR`) point at workspace-relative,
gitignored directories per CONTRACTS §4 — nothing leaks outside /workspace
or into image layers, and reruns stay warm (first cold run compiles all
tools and dependencies; expect minutes). Quality tools install during
`deps` at the versions pinned in verify.sh.

### Suppression policy

Inline suppressions exist for the rare case where a rule misfires on correct
code. They are mechanically policed by `allow_attributes_without_reason`
(denied workspace-wide): every `#[allow(...)]` MUST carry a `reason = "..."`
string, and a justified-but-wrong reason is rejected in review. Test modules
concentrate theirs at the top with a shared justification:

```rust
#![allow(clippy::unwrap_used, reason = "tests build known-valid values and read errors")]
```

Bare `#[allow(clippy::unwrap_used)]` does not compile. Config-level scoping
(workspace lints, clippy.toml thresholds) is always preferred over inline
suppression because it is visible in one place and fails loudly when it
stops matching anything. `unsafe_code` is `forbid` and accepts no
suppression at all.

## Mechanism analysis

Why each gate changes agent behavior, not just detects after the fact:

- **Types absorb what other templates need linters for.** `Quantity` cannot
  hold zero, `Money` cannot be negative, transitions return typed errors —
  whole bug classes vanish before linting starts. The remaining gates police
  exactly what the type system cannot say.
- **Warnings-are-errors without cache invalidation** (`CARGO_BUILD_WARNINGS=
  deny`) removes the classic excuse for leaving a warning alive; the agent's
  iteration loop stays fast while every warning stays fatal.
- **The workspace crate graph makes boundaries physical.** Crossing a layer
  means adding a dependency edge, which is a visible, diffable, gated change
  — not a forgotten import. `cargo tree` reads the same graph the compiler
  consumes, so the arch gate cannot disagree with the build.
- **Coverage fused with nextest kills vacuous tests at the floor**: executing
  code without constraining it cannot hold 91% once real logic lands, and
  proptest's shrinking turns "works for my examples" into a minimal
  counterexample the agent must actually fix.
- **Retries = 0 keeps the signal honest**: flakiness surfaces the day it
  appears, in the run that caused it.
- **cargo-deny beats eyeballing Cargo.lock**: RustSec advisories, yanked
  releases, license drift, duplicate versions, and foreign registries each
  produce a named, greppable failure with the offending package cited.
- **Negative fixtures discipline the gates themselves.** When a clippy
  release renames a lint or a threshold stops matching,
  `bad_examples/assert.sh` fails the same day the enforcement disappears.
  Strictness you cannot observe degrading is not strictness; it is a mood.
