# language-coding-standards

Eight maximally opinionated, CI-enforced project templates — one folder per language, sharing one canonical example domain and one mental model. GitHub Actions is the forcing function that makes coding agents write clean, well-architected code: if generated code fails any gate, the agent must refactor until green. No prompts required.

> **Status:** templates land incrementally. The **Python reference template arrives first** and sets the pattern every other language follows; the remaining seven are ported from it.

## Languages

| Language   | Folder                          | Status  | Language spec                                  |
| ---------- | ------------------------------- | ------- | ---------------------------------------------- |
| Python     | [`python/`](./python)           | planned | [`python/LANG_SPEC.md`](./python/LANG_SPEC.md) |
| TypeScript | [`typescript/`](./typescript)   | planned | [`typescript/LANG_SPEC.md`](./typescript/LANG_SPEC.md) |
| Go         | [`go/`](./go)                   | planned | [`go/LANG_SPEC.md`](./go/LANG_SPEC.md)         |
| Rust       | [`rust/`](./rust)               | planned | [`rust/LANG_SPEC.md`](./rust/LANG_SPEC.md)     |
| Java       | [`java/`](./java)               | planned | [`java/LANG_SPEC.md`](./java/LANG_SPEC.md)     |
| C#         | [`csharp/`](./csharp)           | planned | [`csharp/LANG_SPEC.md`](./csharp/LANG_SPEC.md) |
| Kotlin     | [`kotlin/`](./kotlin)           | planned | [`kotlin/LANG_SPEC.md`](./kotlin/LANG_SPEC.md) |
| Swift      | [`swift/`](./swift)             | planned | [`swift/LANG_SPEC.md`](./swift/LANG_SPEC.md)   |

## Gate matrix

Placeholder — the full gates × languages matrix lands with the final release, once every template has its complete gate set wired into CI.

## Why

- **CI is the style guide.** Coding agents iterate until the pipeline is green, so the pipeline — not prose — defines what acceptable code means. See [docs/PHILOSOPHY.md](docs/PHILOSOPHY.md).
- **Gates must prove they bite.** Every gate ships a negative fixture it demonstrably rejects, asserted in CI, so strictness cannot silently decay. See [docs/PHILOSOPHY.md](docs/PHILOSOPHY.md).
- **One mental model across all eight languages.** Same folder shape, same `verify.sh` phases, same workflow topology everywhere. See [docs/PHILOSOPHY.md](docs/PHILOSOPHY.md) and [docs/CONTRACTS.md](docs/CONTRACTS.md).

## Quickstart

Coming with the first template. Until then, [docs/CONTRACTS.md](docs/CONTRACTS.md) specifies the contract every template implements.

## The forcing-function model

A coding agent treats CI as ground truth about code quality. This repository makes that assumption load-bearing: maximally strict gates run on every change, and an agent whose generated code trips any gate must keep refactoring until every gate passes. The standard is enforced mechanically by the workflow — humans encode it once and stop relitigating it prompt by prompt.

## License

[MIT](LICENSE) © 2026 Steven Buglione.
