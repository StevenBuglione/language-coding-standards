# Contracts

This document is the canonical cross-language contract. Every `<lang>/` template implements exactly what is specified here; language-specific details live in `<lang>/LANG_SPEC.md`. Where a language cannot satisfy a clause idiomatically, LANG_SPEC.md must call out the deviation explicitly and justify it — silence means compliance.

## 1. `verify.sh` phase contract

Each `<lang>/verify.sh`:

- is a bash script beginning with `set -euo pipefail`;
- runs its phases strictly in the canonical order below;
- prints exactly one line per phase to stdout:
  - on success: `GATE <phase>: PASS`
  - on failure: `GATE <phase>: FAIL (<detail>)`
- exits nonzero on the first failing phase.

Canonical phases, in order:

```
deps → format → lint → types → arch → test → coverage → deadcode → security → deps-hygiene → negative
```

| Phase | Meaning |
| -------------- | --------------------------------------------------------------------- |
| `deps` | install locked dependencies plus pinned tools |
| `format` | formatter check only (never rewrite) |
| `lint` | max-strict linter(s); warnings are errors |
| `types` | strict typecheck |
| `arch` | architecture / dependency-boundary contracts; cycles banned |
| `test` | unit (+ property) tests |
| `coverage` | tests run under coverage against the configured floor |
| `deadcode` | unused code and unused-dependency detection |
| `security` | SAST scan |
| `deps-hygiene` | lockfile freshness + vulnerability audit |
| `negative` | run `bad_examples/assert.sh`, proving every fixture trips its gate |

An optional extra phase `mutation` exists only in the nightly full tier (see `full.yml`). It never runs in the default set above.

Usage contract: `./verify.sh [phase...]`

- zero arguments: run all phases, in canonical order;
- explicit arguments: run only the named phases (a subset), still in canonical order — this is how CI jobs split the phase set across jobs.

## 2. Canonical example domain: warehouse order placement

ALL templates implement the identical domain, adapted idiomatically to the language.

### Domain layer (pure)

Value objects:

- `Money` — integer minor units plus an ISO-4217 currency code; invariant: non-negative amount.
- `Quantity` — strictly positive integer.
- `Sku` — non-empty trimmed code.

Entity:

- `Order` — state machine `NEW → PAID → SHIPPED` with invariants:
  - at least 1 line;
  - no duplicate SKUs across lines;
  - total equals the sum of line totals;
  - no mutation after `SHIPPED`.

Domain error types: `InsufficientStock`, `InvalidOrder`, `OrderAlreadyShipped`.

### Ports (interfaces owned by the inner layers)

- `InventoryGateway.reserve(Sku, Quantity) -> Result`
- `PaymentProcessor.charge(Order) -> Result`
- `OrderRepository.save/get`

Binding clarifications:

- `Result` payloads are named: success carries the persisted `Order`; failure carries exactly one of the three domain error types (`InsufficientStock`, `InvalidOrder`, `OrderAlreadyShipped`).
- `OrderRepository.get` takes an Order identifier value and returns order-or-absent (Optional/Result semantics stay idiomatic per language); it never throws for an unknown identifier.
- Money currency mismatch: operations between `Money` values of different currencies raise/return `InvalidOrder` — currency-mismatch is invalid.

### Application layer

`PlaceOrderUseCase` orchestrating validate → reserve → charge → persist, returning typed success/failure results (no exceptions across the boundary where the language has result types).

### Adapters layer

- `InMemoryInventoryGateway` — finite stock map.
- `FakePaymentProcessor` — configurable outcome.
- `InMemoryOrderRepository`.

### Tests

- Unit tests covering every invariant.
- Integration test for the happy path plus each failure path.
- At least 2 property-based tests (for example: Money addition commutativity over random amounts; Order total invariant under randomly generated valid line sets).
- Architecture/boundary tests using the language's designated tool.

## 3. Negative-fixture convention

- `<lang>/bad_examples/` contains one subdirectory per gated rule class.
- Fixtures are excluded from main tooling globs by native scoping (path filters / config sections) — never inline suppressions.
- `<lang>/bad_examples/assert.sh` re-invokes the tools scoped to the fixtures, asserting nonzero exit codes and expected stable rule IDs.
- `assert.sh` is invoked by `verify.sh` as the `negative` phase.
- The top of each `assert.sh` carries a manifest table mapping fixture → gate → expected signal.

## 4. Container preamble

Every CI job and Dockerfile context begins with:

```bash
git config --global --add safe.directory "$GITHUB_WORKSPACE"   # /workspace locally
```

Tool caches point at workspace-relative gitignored directories via per-ecosystem environment variables (e.g. pip cache dirs, Go module/GOCACHE paths, npm cache), so caches never leak outside the workspace and never enter image layers.

## 5. Workflow topology

Per language there is ONE root workflow, `.github/workflows/<lang>.yml`, path-filtered to `<lang>/**`, with three jobs:

| Job      | Phases invoked via `./verify.sh <phases>`        |
| -------- | ------------------------------------------------ |
| `static` | deps, format, lint, types, arch, deadcode        |
| `test`   | test, coverage                                   |
| `supply` | security, deps-hygiene, negative                 |

Each job invokes `./verify.sh` with its phase subset inside a pinned official container image. Workflows declare concurrency group `${{ github.workflow }}-${{ github.ref }}` with cancel-in-progress except on main. The nightly `full.yml` handles mutation/slow tiers. Only first-party `actions/*` refs at version tags are allowed; everything else runs via `docker run` on version-pinned images.

## 6. Local hermetic run

`docker compose run --rm <lang>` builds the runtime image from `<lang>/Dockerfile` and mounts the template folder at `/workspace`. Dockerfiles use official base images ONLY — quality tools are NOT baked in; tools install during the `deps` phase from project manifests at pinned versions.
