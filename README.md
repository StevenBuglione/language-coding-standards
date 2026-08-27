# Language Coding Standards

Opinionated, executable language templates for teaching coding agents to build
small, typed, modular systems without claiming that a green formatter is proof
of production quality.

> **Status:** every language pack is still `experimental`. A green workflow
> means the implemented gates passed; it does not make a pack reference-grade.
> Read [docs/CURRENT_STATUS.md](docs/CURRENT_STATUS.md) and
> [AGENT_HANDOFF-v2.md](AGENT_HANDOFF-v2.md) before promoting or copying a pack.

## What this repository proves

Each language implements the same warehouse-order domain and exposes a
canonical `verify.sh` capability runner. The shared behavior contract is
[docs/CONTRACTS.md](docs/CONTRACTS.md); machine-readable vectors live under
`conformance/v2/`.

The root manifest, `standards/languages.yaml`, is executable policy. Meta CI
checks every implemented pack against its verifier, capability vocabulary,
Dockerfile image, workflow image, and compose service. It must not become a
hand-maintained status brochure again.

## Languages

The default root verification set is:

- Go
- Java
- Python
- Rust
- TypeScript

C#, Kotlin, and Swift are implemented experimental packs but are deliberately
excluded from the default root set. Their individual workflows still run when
relevant shared or language files change.

## Run locally

```bash
# Validate the manifest against all implemented packs.
python3 scripts/manifest.py --check

# Show the default language selection.
python3 scripts/manifest.py --list

# Verify the default set with the repository harness.
bash scripts/verify-all.sh

# Run one language in its declared container.
docker compose run --rm python

# Or invoke a pack directly after bootstrapping its declared toolchain.
cd rust
./verify.sh bootstrap compile unit property integration package
```

Capability output is machine-readable:

```text
GATE unit: PASS
GATE dependency-vulnerability: SKIP_UNSUPPORTED(no pinned scanner yet)
```

A `SKIP_UNSUPPORTED` is an explicit gap, not a pass.

## Repository map

- `docs/CONTRACTS.md` — normative cross-language behavior and gate semantics.
- `docs/CURRENT_STATUS.md` — current implementation matrix and known gaps.
- `AGENT_HANDOFF-v2.md` — researched audit, corrections, and ranked next work.
- `standards/languages.yaml` — language/toolchain/workflow manifest.
- `conformance/v2/` — shared vectors and schema validation.
- `<lang>/LANG_SPEC.md` — language-specific policy and justified deviations.
- `<lang>/verify.sh` — canonical gate runner.
- `.github/workflows/reusable-verify.yml` — shared CI execution topology.

`conformance/v2/gaps.json` is a historical audit snapshot tied to its recorded
baseline SHA. It is not the current status document.
