# ADR-001: Capability vocabulary and status semantics

- Status: Accepted
- Date: 2026-08-26
- Work package: WP1

## Context

The original contract forced every language through a fixed phase list:
`deps`, `format`, `lint`, `types`, `arch`, `test`, `coverage`, `deadcode`,
`security`, `deps-hygiene`, `negative`.

That list hid unlike tools behind shared names. Observed false-greens:

- TypeScript `security` audited an intentionally empty production
  dependency set.
- Rust `deadcode` ran `cargo-shear` (unused dependencies, not dead code).
- Java `deadcode` was also dependency analysis.
- Several `insecure` fixtures exercised lint rules, not the named security
  gate.
- `test` mixed unit, property, and integration, and some languages omitted
  property tests from the normal tier.

A no-op that prints `PASS` trains agents to trust a property that was never
checked.

## Decision

Replace the generic phase vocabulary with named capabilities. Each
capability has a single proof obligation documented in
[CONTRACTS.md](../CONTRACTS.md) §1.

A capability emits exactly one of:

- `PASS` — meaningful work executed and met the policy
- `FAIL` — meaningful work executed and violated policy, or the tool failed
- `SKIP_UNSUPPORTED(<reason>)` — unavailable after documented investigation
- `NOT_APPLICABLE(<proof>)` — the capability truly does not apply

A no-op is never `PASS`.

During one migration release, legacy CLI aliases may map to capabilities
(`deps` → `bootstrap` + `lock-integrity`, `deadcode` → `dead-code` only,
and so on). Unused-dependency analysis must not be aliased to `dead-code`.

Language maturity (`planned`, `experimental`, `candidate`, `reference`)
is recorded in a root manifest in a later work package. `SKIP_UNSUPPORTED`
cannot promote a language to `reference` except for capabilities the root
policy marks optional.

## Consequences

- Verifier scripts and CI jobs must split combined phases (`test`,
  `security`, `deps-hygiene`) into distinct commands.
- Negative fixtures must prove the named capability, not a nearby linter.
- Documentation that says “every gate can fail today” is only true for
  capabilities that have a fixture and a non-no-op implementation.
- Agents get an honest report instead of a green wall of mislabeled tools.
