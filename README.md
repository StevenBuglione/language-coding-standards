# language-coding-standards

Opinionated, CI-enforced project templates — one folder per language, sharing
one canonical example domain and one mental model. GitHub Actions is a forcing
function: if generated code fails a gate, the agent must refactor until green.

This repository is **not reference-grade yet**. Implemented packs are
`experimental`. Planned languages are excluded from default verification.
See [AGENT_HANDOFF.md](AGENT_HANDOFF.md) and [docs/CONTRACTS.md](docs/CONTRACTS.md).

Language state comes from [`standards/languages.yaml`](standards/languages.yaml)
(`planned` → `experimental` → `candidate` → `reference`). A green workflow
alone does not make a pack `reference`.

## Languages

| Language | Folder | State | Spec |
| --- | --- | --- | --- |
| Go | [`go/`](./go) | experimental | [`go/LANG_SPEC.md`](./go/LANG_SPEC.md) |
| Java | [`java/`](./java) | experimental | [`java/LANG_SPEC.md`](./java/LANG_SPEC.md) |
| Python | [`python/`](./python) | experimental | [`python/LANG_SPEC.md`](./python/LANG_SPEC.md) |
| Rust | [`rust/`](./rust) | experimental | [`rust/LANG_SPEC.md`](./rust/LANG_SPEC.md) |
| TypeScript | [`typescript/`](./typescript) | experimental | [`typescript/LANG_SPEC.md`](./typescript/LANG_SPEC.md) |
| C# | [`csharp/`](./csharp) | experimental (not in default verify) | [`csharp/LANG_SPEC.md`](./csharp/LANG_SPEC.md) |
| Kotlin | [`kotlin/`](./kotlin) | experimental (not in default verify) | [`kotlin/LANG_SPEC.md`](./kotlin/LANG_SPEC.md) |
| Swift | [`swift/`](./swift) | experimental (not in default verify) | [`swift/LANG_SPEC.md`](./swift/LANG_SPEC.md) |

Default `scripts/verify-all.sh` selects the five experimental packs. It does
not build C#, Kotlin, or Swift.

## Capabilities

Gates are named capabilities (`compile`, `unit`, `property`, `sast`,
`dependency-vulnerability`, `conformance`, …), not a one-size-fits-all
`security` / `deadcode` / `test` slot. A no-op cannot report `PASS`.
See [docs/CONTRACTS.md](docs/CONTRACTS.md) and
[ADR-001](docs/adr/001-capability-vocabulary.md).

Shared behavior is defined by [`conformance/v2/`](conformance/v2/). Current
implementations fail those vectors until the domain workflow is corrected
(successful placement must persist `PAID`).

## Why

- **CI is a forcing function, not a substitute for a domain contract.** See
  [docs/PHILOSOPHY.md](docs/PHILOSOPHY.md).
- **Gates must prove they bite.** Negative fixtures belong to a named
  capability. See [docs/PHILOSOPHY.md](docs/PHILOSOPHY.md).
- **One mental model, language-native idioms.** Same outcomes, not identical
  syntax. See [docs/CONTRACTS.md](docs/CONTRACTS.md).

## Quickstart

```bash
python conformance/v2/validate.py
python scripts/manifest.py --list
docker compose run --rm python
scripts/verify-all.sh python
```

Hermetic local runs: `docker compose run --rm <lang>`. Root verification
writes `artifacts/verification.json`.

## License

[MIT](LICENSE) © 2026 Steven Buglione.
