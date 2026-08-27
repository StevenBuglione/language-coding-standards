# ADR-007: Supported toolchain and version policy

- Status: Accepted
- Date: 2026-08-26
- Work package: WP2

## Context

Each pack pins a toolchain in its Dockerfile and lock/manifest. Comments
sometimes called a floating tag a pin. Docker tags move; digests do not.
Action major tags move; commit SHAs do not.

## Decision

- The supported toolchain for a language is the version recorded in the
  manifest plus the language `LANG_SPEC.md`.
- Image tags in Dockerfiles and Compose remain the human-readable name.
  Immutable pins are digest values, filled in WP3 when the digest is
  recorded next to the tag.
- Actions pin to a 40-character commit SHA with a version comment (WP3).
- Tool upgrades run fixture and conformance proof before merge.
- Renovate (or equivalent) must see native lockfiles and documented pins.

Current experimental toolchains:

| Language | Toolchain |
| --- | --- |
| Python | CPython 3.13 + uv 0.12.6 |
| TypeScript | Node 24 + pnpm via Corepack |
| Go | Go 1.26 |
| Rust | 1.98.0 |
| Java | JDK 25 + Maven 3.9 wrapper |

## Consequences

A Dockerfile `FROM` without a digest is not yet reference-grade. WP3
records digests. A language cannot be `reference` while the image tag
floats.
