# Contracts

This document is the canonical cross-language contract **v2**. Every `<lang>/`
template implements exactly what is specified here; language-specific details
live in `<lang>/LANG_SPEC.md`. Where a language cannot satisfy a clause
idiomatically, LANG_SPEC.md must call out the deviation explicitly and justify
it — silence means compliance.

Shared behavior is proven by `conformance/v2/` vectors, not by independently
invented language tests. A language-specific test that encodes different
semantics is a defect.

Related decisions: [ADR-001](adr/001-capability-vocabulary.md),
[ADR-002](adr/002-canonical-domain-v2.md),
[ADR-003](adr/003-supply-chain-untrusted-output.md).

## 1. Capability contract

Each `<lang>/verify.sh`:

- is a bash script beginning with `set -euo pipefail`;
- runs requested capabilities and prints exactly one line per capability to stdout:
  - on success: `GATE <capability>: PASS`
  - on failure: `GATE <capability>: FAIL (<detail>)`
  - unsupported: `GATE <capability>: SKIP_UNSUPPORTED(<reason>)`
  - inapplicable: `GATE <capability>: NOT_APPLICABLE(<proof>)`
- exits nonzero on the first `FAIL`;
- never reports `PASS` for a no-op.

A capability may report `PASS`, `FAIL`, `SKIP_UNSUPPORTED(reason)`, or
`NOT_APPLICABLE(proof)`. `SKIP_UNSUPPORTED` is allowed for an `experimental`
language. A `reference` language may use it only when root policy classifies
that capability as optional.

### 1.1 Capabilities

| Capability | A `PASS` must prove | Forbidden false-green |
| --- | --- | --- |
| `bootstrap` | Required dependencies/tools can be obtained at pinned versions | Merely checking that a package manager exists |
| `format` | All governed source/config files match the canonical formatter | Ignoring unformatted generated or test code without policy |
| `lint` | Language-native static quality/style rules pass | Calling a vulnerability scanner a linter or vice versa |
| `compile` | Production and test code compile/type-check under the supported configuration | Checking only production while tests use unchecked types |
| `architecture` | Forbidden dependency directions and cycles are rejected | Hard-coding today's files so a new module bypasses the rule |
| `unit` | Unit tests execute and zero tests is an error | A test command that succeeds after all tests are deleted |
| `property` | Generative/property tests execute with reproducible seeds | Counting example-based tests as property tests |
| `integration` | Ports/adapters are wired and observable side effects are verified | Calling unit tests integration tests because they cross files |
| `package` | The distributable binary/library/package is built, installed, and smoke-tested | `--noEmit`, `check`, or compile-only success |
| `coverage` | Line and branch/region coverage meet committed floors and critical-file minima | Global line-only percentage with untested core workflow |
| `dead-code` | Unreachable/unused production declarations are detected according to a documented public-API policy | Running an unused-dependency tool |
| `sast` | Source-level security defects are scanned | Auditing a dependency lockfile only |
| `dependency-vulnerability` | Runtime and build/test dependencies are checked against a vulnerability source | Auditing an empty subset and reporting meaningful security coverage |
| `dependency-policy` | Licenses, sources, duplicates, forbidden packages, and unused/direct dependency policy pass | Calling source lint dependency policy |
| `lock-integrity` | Manifest/lock agreement, wrapper integrity, and offline/frozen resolution are proven | Regenerating a lockfile and accepting the diff automatically |
| `negative-fixtures` | Every required capability's detector catches a stable known violation | Proving one linter rule and claiming all gates bite |
| `mutation` | Mutants are executed and the committed kill threshold is met | Printing `SKIP` in the only scheduled full workflow |
| `reproducibility` | Two clean artifact builds are compared with normalized, documented exceptions | Two incremental runs in the same dirty workspace |
| `conformance` | Shared language-independent behavior vectors pass | Language-specific tests that encode divergent semantics |

### 1.2 Legacy CLI aliases

During migration, `./verify.sh [phase...]` may accept the historical names.
Remove the aliases after one documented migration release.

| Legacy phase | Maps to |
| --- | --- |
| `deps` | `bootstrap` + `lock-integrity` |
| `types` | `compile` |
| `arch` | `architecture` |
| `test` | `unit` + `property` + `integration` |
| `security` | `sast` + `dependency-vulnerability` |
| `deps-hygiene` | `dependency-policy` + `lock-integrity` |
| `deadcode` | `dead-code` only; unused-dependency analysis must not map here |
| `negative` | `negative-fixtures` |

Usage: `./verify.sh [capability-or-alias...]`

- zero arguments: run the language's default capability set, in the order
  declared by the language spec;
- explicit arguments: run only the named capabilities, still in canonical
  order.

## 2. Canonical domain: warehouse order placement v2

ALL templates implement the identical domain, adapted idiomatically. The
normative numeric and workflow values live in `conformance/v2/catalog.json`
and the suite files; this section is the human-readable statement of those
rules.

### 2.1 Money

- Store a non-negative integer number of minor units.
- Shared range: `0` through `9007199254740991` inclusive.
- Amounts on the wire and in conformance vectors are decimal strings so
  values remain lossless above IEEE-754 safe-integer boundaries that JSON
  numbers cannot represent.
- Every addition and multiplication is checked for overflow against that
  maximum. Overflow is `InvalidOrder`, never wrap, saturate, or coerce.
- Currency mismatch is rejected before arithmetic.
- Currency codes are **ISO-style**: exactly three uppercase ASCII letters
  (`^[A-Z]{3}$`). Codes such as `ZZZ` are valid. This is not ISO-4217
  membership validation. Do not claim real ISO-4217 compliance while `ZZZ`
  passes.
- Currency is non-null and immutable.

### 2.2 Quantity

- Strictly positive integer in the shared range `1` through `2147483647`.
- Zero, negatives, fractions, and values above the maximum are `InvalidOrder`.
- JSON booleans and language booleans are `InvalidOrder`. Python must reject
  `bool` explicitly; `bool` is a subclass of `int`, so `True` would otherwise
  pass a `value > 0` check.

### 2.3 SKU

- Strip only ASCII space, tab, CR, and LF from both ends.
- Reject an empty result.
- Preserve interior text and case. `sku-a` is not `SKU-A`.
- U+00A0 and other non-ASCII whitespace are not stripped.
- UTF-8 byte length of the normalized code must be `1..=64`.
- Duplicate detection uses the normalized representation.

### 2.4 Order ID and time

- The domain receives an `OrderId`; it does not read randomness, a
  process-global counter, wall-clock time, or environment state.
- The application injects `OrderIdGenerator` and `Clock` ports where needed.
- Conformance tests use deterministic fakes.

### 2.5 Order aggregate

- Constructor inputs: injected `OrderId`, validated non-empty lines.
- Reject duplicate normalized SKUs.
- Reject mixed currencies at construction rather than delaying failure until
  `total()`.
- Store defensive immutable snapshots.
- Initial state is `NEW`.
- Only `NEW → PAID → SHIPPED` is legal.
- `pay` on `PAID` is `InvalidOrder`.
- Any mutation on `SHIPPED` is `OrderAlreadyShipped`.
- Total is computed with checked arithmetic and cannot become stale.
- Optimistic version starts at `0` for a newly constructed aggregate.
  Persistence increments version on a successful save.

### 2.6 Place-order workflow

One explicit, testable policy across all languages:

1. Validate all input and construct the `NEW` order with an injected ID.
2. Call one atomic `reserveAll(orderId, lines, idempotencyKey)` operation.
   It returns a reservation token or `InsufficientStock`.
3. Charge the order total with the same idempotency key. It returns a charge
   receipt or `PaymentDeclined`.
4. On charge failure, release the reservation. If release fails, return
   `InfrastructureFailure` or `CompensationFailure` according to the failed
   stage.
5. After a successful charge, call the domain transition to mark the order
   `PAID`.
6. Save the paid order with optimistic version / expected-state semantics.
7. On save failure, refund/void the charge and release the reservation.
   Model compensation failure explicitly as `CompensationFailure`.
8. Return an immutable persisted snapshot only after save succeeds.

`PlaceOrderCommand` includes an idempotency key.

- Retrying the same key and payload cannot double-charge or double-reserve.
- Reusing a key with a different payload is `InvalidOrder`.
- Concurrent reservations cannot oversell stock.
- In-memory adapters are thread-safe if the template claims concurrent
  correctness.

A single in-memory `UnitOfWork` that atomically reserve/charge/transition/save
is an acceptable educational simplification only if it still produces the
same observable outcomes as this policy, including compensation results.
Silently teaching a non-atomic workflow that charges the customer and
persists `NEW` is forbidden.

### 2.7 Error vocabulary

Expected failures cross the use-case boundary as typed values. The minimum
vocabulary is:

| Error | Meaning |
| --- | --- |
| `InvalidOrder` | Structural invariant or illegal state transition other than shipped mutation |
| `InsufficientStock` | Atomic reservation could not cover every line |
| `PaymentDeclined` | Charge was refused |
| `PersistenceConflict` | Optimistic save lost a compare-and-set race |
| `InfrastructureFailure` | Adapter/runtime failure with stage and retryability metadata |
| `CompensationFailure` | Refund/release itself failed after a partial success |
| `OrderAlreadyShipped` | Mutation of a shipped aggregate |

The `PlaceOrder` result need not include an unreachable
`OrderAlreadyShipped` variant. Programmer bugs and invariant-corrupting
states must not be mislabeled as business failures.

### 2.8 Ports

Application-owned outbound ports, adapted idiomatically:

- `InventoryGateway.reserveAll(orderId, lines, idempotencyKey) -> reservation token | InsufficientStock`
- `InventoryGateway.release(reservationToken) -> unit | CompensationFailure | InfrastructureFailure`
- `PaymentProcessor.charge(order, idempotencyKey) -> receipt | PaymentDeclined`
- `PaymentProcessor.refund(receipt) -> unit | CompensationFailure | InfrastructureFailure`
- `OrderRepository.save(order, expectedVersion) -> snapshot | PersistenceConflict`
- `OrderRepository.get(orderId) -> snapshot | absent` — unknown identifiers never raise
- `OrderIdGenerator.next() -> OrderId`
- `Clock.now() -> timestamp`

Repository reads and writes do not expose a mutable alias to stored state.

### 2.9 Adapters

Reference adapters remain in-memory and fake:

- `InMemoryInventoryGateway` — finite stock map, atomic `reserveAll`, thread-safe.
- `FakePaymentProcessor` — configurable decline, records receipts, idempotent by key.
- `InMemoryOrderRepository` — snapshot isolation, optimistic version, no aliasing.

## 3. Shared conformance vectors

`conformance/v2/` is the machine-readable behavior contract.

- `schema.json` describes suite documents.
- `catalog.json` lists required case ids and shared numeric limits.
- `suites/*.json` are the vectors every language must load.
- `gaps.json` records which vectors the audited baseline still fails.
- `validate.py` is the language-independent schema/structure validator.

A change to these vectors must trigger every `candidate` and `reference`
language workflow once those workflows exist.

Language adapters (WP4) execute the vectors against the language pack.
Until then, `python conformance/v2/validate.py` only proves the vectors are
well-formed. Current implementations are expected to fail the cases listed
in `gaps.json`, including successful placement persisting `PAID`.

## 4. Negative-fixture convention

- `<lang>/bad_examples/` contains one subdirectory per gated rule class.
- Fixtures are excluded from main tooling globs by native scoping (path
  filters / config sections) — never inline suppressions.
- `<lang>/bad_examples/assert.sh` re-invokes the tools scoped to the
  fixtures, asserting nonzero exit codes and expected stable rule IDs.
- A machine-readable fixture manifest must map fixture → capability →
  exact diagnostic. A fixture that proves a nearby linter is not proof of
  `sast`, `dead-code`, or `dependency-vulnerability`.

## 5. Container preamble

Every CI job and Dockerfile context begins with:

```bash
git config --global --add safe.directory "$GITHUB_WORKSPACE"   # /workspace locally
```

Tool caches point at workspace-relative gitignored directories via
per-ecosystem environment variables, so caches never leak outside the
workspace and never enter image layers.

Compiler, test, and dependency output is untrusted data. Runners must strip
or escape ANSI control sequences before placing logs into agent context.
See [ADR-003](adr/003-supply-chain-untrusted-output.md).

## 6. Workflow topology

Per implemented language there is ONE root workflow,
`.github/workflows/<lang>.yml`, path-filtered to that language **and** to
shared contract/conformance paths, with jobs that invoke `./verify.sh`
inside a pinned official container image.

Shared contract changes (`docs/CONTRACTS.md`, `conformance/v2/**`,
`standards/**` once present) must invalidate every candidate/reference
language check.

Image tags are not pins. Pins are digest + full action SHA; that hardening
is specified in ADR-003 and implemented in the CI work package.

## 7. Local hermetic run

`docker compose run --rm <lang>` builds the runtime image from
`<lang>/Dockerfile` and mounts the template folder at `/workspace`.
Dockerfiles use official base images ONLY — quality tools are NOT baked in;
tools install during `bootstrap` from project manifests at pinned versions.

The root verifier must select languages from the implemented-state manifest
once that manifest exists. Planned languages are not part of the default
verification set.
