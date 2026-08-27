# Contracts

This document is the canonical cross-language contract **v2**. Every `<lang>/`
template implements the behavior and evidence semantics specified here;
language-specific details live in `<lang>/LANG_SPEC.md`. Where a language
cannot satisfy a clause idiomatically, its spec must call out the deviation and
justify it. Silence means compliance.

This file is normative. Implementation progress is deliberately separated into
[CURRENT_STATUS.md](CURRENT_STATUS.md). Historical audit snapshots such as
`conformance/v2/gaps.json` never override current verifier evidence.

Related decisions: [ADR-001](adr/001-capability-vocabulary.md),
[ADR-002](adr/002-canonical-domain-v2.md), and
[ADR-003](adr/003-supply-chain-untrusted-output.md).

## 1. Capability contract

Each `<lang>/verify.sh`:

- is a Bash script beginning with `set -euo pipefail`;
- runs requested capabilities in canonical order;
- prints exactly one result line per requested capability to stdout;
- sends tool diagnostics to stderr;
- exits nonzero on the first failure; and
- never reports `PASS` for a no-op or zero-test command.

Result forms are:

```text
GATE <capability>: PASS
GATE <capability>: FAIL (<detail>)
GATE <capability>: SKIP_UNSUPPORTED(<reason>)
GATE <capability>: NOT_APPLICABLE(<proof>)
```

`SKIP_UNSUPPORTED` is an explicit gap. It is allowed for an `experimental`
pack. A `reference` pack may use it only where root policy classifies the
capability as optional. Installation, service, or configuration failures must
not be converted into skips.

### 1.1 Capabilities

| Capability | A `PASS` must prove | Forbidden false-green |
| --- | --- | --- |
| `bootstrap` | Required dependencies and tools can be obtained at pinned versions | Merely checking that a package manager exists |
| `format` | All governed source/config files match the canonical formatter | Ignoring tests/generated files without documented policy |
| `lint` | Language-native static quality/style rules pass | Calling a vulnerability scanner a linter |
| `compile` | Production and test code compile/type-check under the supported configuration | Checking production while tests use unchecked types |
| `architecture` | Forbidden dependency directions and cycles are structurally rejected | Hard-coding today's files so new modules bypass the rule |
| `unit` | Unit tests execute and zero tests is an error | Success after all tests are deleted or renamed |
| `property` | Generative/property tests execute with reproducible seeds | Counting ordinary examples or doctests as property tests |
| `integration` | Ports/adapters are wired and observable side effects are verified | Relabeling unit tests because they cross files |
| `package` | The distributable is built, installed/consumed, and smoke-tested from packaged contents | `--noEmit`, `check`, compile-only, or skipped package verification |
| `coverage` | Line and branch/region coverage meet committed floors and critical-file minima | A global line-only percentage with an untested workflow core |
| `dead-code` | Unreachable/unused production declarations are detected under a documented public-API policy | Running only an unused-dependency tool |
| `sast` | Source-level security defects are scanned | Auditing only dependency metadata |
| `dependency-vulnerability` | Runtime and build/test dependencies are checked against a vulnerability source | Auditing an empty or conveniently filtered subset |
| `dependency-policy` | Licenses, sources, duplicates, forbidden packages, and unused/direct dependency policy pass | Calling source lint dependency policy |
| `lock-integrity` | Manifest/lock agreement, wrapper integrity, and frozen resolution are proven | Regenerating a lock and accepting drift automatically |
| `negative-fixtures` | Required detectors catch stable known violations | Proving one nearby rule and claiming every gate bites |
| `mutation` | Mutants execute and the committed kill threshold is met | Configuring a mutator that no scheduled workflow runs |
| `reproducibility` | Two clean artifact builds compare equal after narrow documented normalization | Two incremental runs in one dirty workspace |
| `conformance` | Shared language-independent vectors execute completely | Language-specific tests that encode divergent semantics |

### 1.2 Legacy aliases

During migration, a verifier may accept these historical names:

| Legacy phase | Maps to |
| --- | --- |
| `deps` | `bootstrap` + `lock-integrity` |
| `types` | `compile` |
| `arch` | `architecture` |
| `test` | `unit` + `property` + `integration` |
| `security` | `sast` + `dependency-vulnerability` |
| `deps-hygiene` | `dependency-policy` + `lock-integrity` |
| `deadcode` | `dead-code`; unused-dependency analysis must not map here |
| `negative` | `negative-fixtures` |

With zero arguments, a verifier runs its default set. Explicit arguments select
only named capabilities or aliases, still in canonical order.

## 2. Canonical domain: warehouse order placement v2

All templates implement the same domain idiomatically. Normative numeric and
workflow values live in `conformance/v2/catalog.json` and the suite files. This
section is their human-readable statement.

### 2.1 Money

- Store a non-negative integer number of minor units.
- Shared range: `0..=9007199254740991`.
- Wire/vector amounts are decimal strings so values remain lossless across
  JSON implementations.
- Addition and multiplication are checked against the shared maximum; overflow
  is `InvalidOrder`, never wrap, saturation, or coercion.
- Currency mismatch is rejected before arithmetic.
- Currency codes match `^[A-Z]{3}$`; `ZZZ` is valid. This is ISO-style shape,
  not ISO-4217 membership validation.
- Currency is non-null and immutable.

### 2.2 Quantity

- Strictly positive integer in `1..=2147483647`.
- Zero, negatives, fractions, booleans, and values above the maximum are
  `InvalidOrder`.
- Python must reject `bool` explicitly because it subclasses `int`.

### 2.3 SKU

- Strip ASCII space, tab, CR, and LF from both ends only.
- Reject an empty result.
- Preserve interior text and case.
- Do not strip U+00A0 or other non-ASCII whitespace.
- UTF-8 byte length of the normalized value is `1..=64`.
- Duplicate detection uses the normalized representation.

### 2.4 Order ID and time

- The domain receives an `OrderId`; it never reads randomness, a process-global
  counter, wall-clock time, or environment state.
- The application injects `OrderIdGenerator` and `Clock` ports where needed.
- Conformance tests use deterministic fakes.

### 2.5 Order aggregate

- Constructor input is an injected ID plus validated non-empty lines.
- Reject duplicate normalized SKUs and mixed currencies at construction.
- Store defensive immutable snapshots.
- Initial state is `NEW`.
- Only `NEW -> PAID -> SHIPPED` is legal.
- `pay` on `PAID` is `InvalidOrder`.
- Any mutation on `SHIPPED` is `OrderAlreadyShipped`.
- Total uses checked arithmetic and cannot become stale.
- Optimistic version starts at `0`; persistence increments it on successful
  save.

### 2.6 Place-order workflow

The observable policy is:

1. Validate input and construct the `NEW` order with an injected ID.
2. Call atomic `reserveAll(orderId, lines, idempotencyKey)` and receive a
   reservation token or `InsufficientStock`.
3. Charge the order total with the same idempotency key and receive a receipt
   or `PaymentDeclined`.
4. On charge failure, release the reservation. Model release failure explicitly.
5. After successful charge, transition the order to `PAID`.
6. Save the paid order with optimistic expected-version semantics.
7. On save failure, refund/void the charge and release the reservation. Model
   compensation failure explicitly.
8. Return an immutable persisted snapshot only after save succeeds.

`PlaceOrderCommand` includes an idempotency key. Retrying the same key/payload
cannot double-charge or double-reserve. Reusing a key for a different payload is
`InvalidOrder`. Concurrent reservations cannot oversell. An in-memory
`UnitOfWork` is acceptable only when its observable outcomes, including
compensation, match this policy.

### 2.7 Error vocabulary

Expected use-case failures are typed values:

| Error | Meaning |
| --- | --- |
| `InvalidOrder` | Structural invariant or illegal transition other than shipped mutation |
| `InsufficientStock` | Atomic reservation cannot cover every line |
| `PaymentDeclined` | Charge is refused |
| `PersistenceConflict` | Optimistic save loses a compare-and-set race |
| `InfrastructureFailure` | Adapter/runtime failure with stage and retryability metadata |
| `CompensationFailure` | Refund/release fails after partial success |
| `OrderAlreadyShipped` | Mutation of a shipped aggregate |

Programmer bugs and invariant-corrupting states must not be mislabeled as
business failures.

### 2.8 Ports

Application-owned outbound ports, adapted idiomatically:

- `InventoryGateway.reserveAll(orderId, lines, idempotencyKey)`
- `InventoryGateway.release(reservationToken)`
- `PaymentProcessor.charge(order, idempotencyKey)`
- `PaymentProcessor.refund(receipt)`
- `OrderRepository.save(order, expectedVersion)`
- `OrderRepository.get(orderId)` — unknown IDs are absent, never exceptional
- `OrderIdGenerator.next()`
- `Clock.now()`

Repository reads and writes never expose mutable aliases to stored state.

### 2.9 Adapters

Reference adapters remain in-memory/fake:

- finite, atomic, thread-safe inventory;
- configurable, idempotent fake payment processing with recorded receipts; and
- snapshot-isolated optimistic order persistence.

## 3. Shared conformance vectors

`conformance/v2/` is the machine-readable behavior contract:

- `schema.json` describes suite documents;
- `catalog.json` lists required IDs and shared limits;
- `suites/*.json` are the vectors;
- `validate.py` validates language-independent schema and structure; and
- `gaps.json` preserves a historical audit snapshot tied to its recorded
  baseline SHA. It is not current status.

A language may report `conformance: PASS` only when its adapter executes the
complete required catalog against production APIs and fails for missing,
duplicate, ignored, or mismatched vectors. Schema validation alone is not
language conformance.

Changes under `conformance/v2/**`, this contract, the manifest, or shared
workflow infrastructure must trigger every implemented language workflow,
including opted-out experimental packs.

Current implementation coverage is documented in
[CURRENT_STATUS.md](CURRENT_STATUS.md), not in this normative contract.

## 4. Negative-fixture convention

- `<lang>/bad_examples/` contains stable violations grouped by capability/rule.
- Fixtures are excluded from main globs by native path/config scoping, never
  production inline suppressions.
- `<lang>/bad_examples/assert.sh` re-invokes the detector against the fixture,
  asserts a nonzero exit, and checks a stable diagnostic identifier.
- A machine-readable map should identify fixture -> capability -> diagnostic.
- A linter fixture is not proof for SAST, dead-code, dependency vulnerability,
  package consumption, zero-test detection, or reproducibility.

## 5. Container preamble and untrusted output

Where `git` is installed, CI and local container entry points run:

```bash
git config --global --add safe.directory "$GITHUB_WORKSPACE"
```

Slim official images may omit Git; `actions/checkout` then uses its REST archive
path. In that case the safe-directory operation is inapplicable and the
workflow must not fail before the pack's declared setup. A verifier must not
assume Git is present unless it declares Git as a bootstrap dependency.

Tool caches live in workspace-relative ignored directories and never enter
image layers. Compiler, test, dependency, and package-manager output is
untrusted. Strip or escape terminal control sequences before placing logs into
agent context. See ADR-003.

## 6. Workflow topology and pinning

Each implemented language has one root workflow,
`.github/workflows/<lang>.yml`, path-filtered to the language and shared
contract/conformance infrastructure. It invokes the canonical verifier through
`.github/workflows/reusable-verify.yml` in the language's declared official
container.

GitHub actions must be pinned by full commit SHA. Container tags are not
immutable pins: every workflow and Dockerfile must ultimately use a reviewed
digest, and the manifest must record and validate the same digest. Until that
is implemented, packs remain experimental and current status must say so.

Shared contract, conformance, manifest, and reusable-workflow changes trigger
all implemented language checks, not only default, candidate, or reference
packs.

## 7. Local hermetic run

`docker compose run --rm <lang>` builds `<lang>/Dockerfile` and mounts the pack
at `/workspace`. Dockerfiles use official base images. Quality tools are not
baked into an opaque custom image; bootstrap obtains pinned versions from
project manifests or immutable verified releases.

The root verifier selects languages from `standards/languages.yaml`. Planned
languages are excluded. Implemented packs with `inDefault: false` remain
individually testable and must still be covered by shared-change workflows.
