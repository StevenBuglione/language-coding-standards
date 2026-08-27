# ADR-005: Planned-language onboarding

- Status: Accepted
- Date: 2026-08-26
- Work package: WP2

## Context

C#, Kotlin, and Swift are declared in README and `verify-all.sh` but have
no directories. The default all-language path therefore cannot succeed.
The handoff forbids adding empty folders just to make Compose parse.

## Decision

A language starts at `planned` in `standards/languages.yaml` with:

- no required directory;
- no Compose service;
- no default verification;
- an onboarding blueprint in this ADR and AGENT_HANDOFF.md §§18–20.

Promotion to `experimental` requires: directory, Dockerfile, `verify.sh`,
`LANG_SPEC.md`, negative-fixture skeleton, domain sample, and a workflow
or matrix entry. Conformance may still fail.

Promotion to `candidate` requires the WP4 vectors to pass, two clean
container runs, and honest capability status.

Onboarding order: C#, then Kotlin, then Swift, unless a maintainer owns a
different order. Planned languages must not block stabilization of the
five implemented packs.

## Consequences

`scripts/verify-all.sh` and Compose ignore planned languages. Adding a
folder without updating the manifest is a consistency failure once that
language is marked experimental.
