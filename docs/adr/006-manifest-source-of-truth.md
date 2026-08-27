# ADR-006: Manifest as source of truth

- Status: Accepted
- Date: 2026-08-26
- Work package: WP2

## Context

README, Compose, `verify-all.sh`, and workflows listed languages
independently. Three of those lists included languages that do not exist.

## Decision

`standards/languages.yaml` is the only list of languages and states.

The file is JSON-compatible YAML so the loader stays in the Python
standard library.

Derived views:

- README language table
- Compose default services
- root verifier default selection
- workflow matrix / required-check documentation

A candidate or reference language missing directory, Dockerfile, verifier,
spec, or workflow is a failed consistency check. Experimental languages
may still be missing a conformance adapter until WP4.

## Consequences

Do not hand-edit three lists. Change the manifest, then update derived
files in the same commit. `scripts/manifest.py --list` is the machine
check for the default set.
