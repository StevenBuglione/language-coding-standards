# ADR-004: Thresholds and baseline methodology

- Status: Accepted
- Date: 2026-08-26
- Work package: WP2

## Context

Coverage and mutation floors in this repository were presented as universal
quality truth. They are project defaults chosen so the sample stays small
enough to maintain and strict enough that deleting tests fails the build.

Environment variables such as `MUTATION_FLOOR` can currently lower a gate
in CI. That is a false-green.

## Decision

- Thresholds live in committed configuration (`LANG_SPEC.md`, tool config,
  and `standards/languages.yaml`).
- CI must not honor environment variables that lower a floor.
- Changing a threshold requires an ADR amendment and a fixture or
  conformance note explaining the evidence.
- A language may not be marked `reference` on a global line-coverage
  percentage alone; critical workflow files need their own minima.

## Consequences

Verifier scripts that read `MUTATION_FLOOR` from the environment in CI are
defects. Nightly mutation still uses the committed floor.
