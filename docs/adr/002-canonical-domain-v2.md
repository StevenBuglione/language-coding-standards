# ADR-002: Canonical domain v2 and compensation policy

- Status: Accepted
- Date: 2026-08-26
- Work package: WP1

## Context

All five implemented `PlaceOrder` workflows reserve inventory, charge
payment, and persist the order without transitioning `NEW → PAID`. The
reference sample therefore teaches agents to persist an unpaid state after
successfully charging the customer.

Related defects in the v1 contract:

- “Exactly three errors” cannot represent payment decline, persistence
  conflict, infrastructure failure, or compensation failure.
- IDs are generated from ambient global state inside the domain.
- Money range and overflow are unspecified; Java `int` arithmetic can wrap.
- Currency was documented as ISO-4217 while most packs accept any
  `[A-Z]{3}` (including `ZZZ`); Java `java.util.Currency` rejects `ZZZ`.
- Python `bool` satisfies integer quantity checks.
- SKU trimming used language-native `strip`, which is not the same set of
  characters across runtimes.
- Repositories can expose mutable aliases to stored aggregates.
- Multi-line reservation is not atomic; payment decline does not release
  stock.

Tooling cannot compensate for a semantically broken reference application.

## Decision

Adopt **domain contract v2**, specified in [CONTRACTS.md](../CONTRACTS.md)
§2 and encoded as JSON in `conformance/v2/`.

Currency policy is **ISO-style** (`^[A-Z]{3}$`), not ISO-4217 membership.
`ZZZ` is valid. A later ADR may adopt a versioned ISO-4217 dataset; v2
will not claim that dataset.

Shared numeric limits, chosen so every implemented language can represent
them after WP4:

- Money minor units: `0..=9007199254740991`
- Quantity: `1..=2147483647`
- SKU UTF-8 bytes: `1..=64`

Place-order is atomic reservation plus compensation:

1. validate and construct `NEW` with an injected id
2. `reserveAll`
3. charge with the same idempotency key
4. release on payment decline
5. domain `pay()` → `PAID`
6. save with expected version
7. refund and release on save failure
8. return an immutable snapshot only after save

Idempotent retries must not double-charge. Concurrent reservations must not
oversell. Compensation failure is a first-class error.

`gaps.json` lists the v2 vectors that the audited baseline
(`e856a5add491f1eebd58273224945a0f4b3ba797`) still fails. Language packs
are not rewritten in WP1; the vectors are supposed to fail until WP4.

## Consequences

- Five language packs will change together against the same vectors in WP4.
- Java money storage must move off overflowing `int` / `java.util.Currency`
  as the public currency type.
- Python must reject `bool` at quantity (and any other integer) boundaries.
- Go exported structs and TypeScript `readonly` are not sufficient
  encapsulation; constructors and snapshots must enforce the contract.
- Tests that currently assert `status is NEW` after a successful charge are
  documenting the bug and must flip with WP4.
