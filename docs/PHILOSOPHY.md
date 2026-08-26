# Philosophy

## The premise: CI is the style guide

A coding agent does not read a contributing guide and resolve to do better. It writes code, runs the checks, reads the failures, and iterates until the pipeline is green. That loop is the agent's entire working definition of "done." Any property you want in the code — strictness, architecture, honesty of tests — must therefore live inside the pipeline, expressed mechanically, or the agent will not reliably produce it.

This repository draws the obvious conclusion: **CI *is* the style guide.** Each of the eight language templates here is a bundle of maximally strict gates enforced by GitHub Actions. GitHub Actions is the forcing function that makes coding agents write clean, well-architected code: if generated code fails any gate, the agent must refactor until green. No prompts required. Humans argue about standards once, encode them as gates, and stop relitigating them in review comments forever after.

## The eight principles

Every template implements the following principles.

1. **Every warning is an error.** Compilers and linters ship defaults tuned for legacy codebases; we retune them. No warning survives as a warning — a build that prints one is a failing build.
2. **Suppression must be loud and justified.** Escape hatches exist (inline disables, baselines), but each demands a written justification next to it, and suppressions surface in review. Silent suppression is treated as tampering with the gates.
3. **Compiler > convention.** Prefer type-system and architecture enforcement at compile time over convention documented in prose. If a machine can reject it, it never depends on discipline.
4. **Tests must assert something.** Coverage + mutation floors kill vacuous tests — tests that execute code without constraining it. A test that cannot fail meaningfully does not count.
5. **Architecture is executable.** Layered contracts are encoded as code — pure domain, orchestrating application, adapters at the edges — and the arch phase rejects violations such as dependency cycles or adapters reaching inward.
6. **Reproducibility is non-negotiable.** Toolchains are pinned, installs are lockfile-only, and containers are version-pinned official images. Two runs of `verify.sh` on two machines do byte-for-byte comparable work.
7. **Gates prove themselves via bad_examples.** Every gate ships a fixture it demonstrably rejects, and CI asserts those rejections happen. A gate that cannot prove it bites gets fixed or removed.
8. **One mental model across all eight languages.** Same folder shape, same `verify.sh` phases, same workflow topology. Learning one template teaches you the other seven; only the idioms differ.

None of these are aspirational values. Each maps to a concrete phase of `verify.sh` (see [CONTRACTS.md](CONTRACTS.md)), each phase prints `GATE <phase>: PASS` on success, and each can fail the build today.

## The negative-fixture pattern

Strict configuration decays silently. A linter upgrade drops or renames a rule; a config flag rots; a rule stops matching modern syntax — and nothing fails, because the happy-path code was already compliant. Strictness you cannot observe degrading is not strictness; it is a mood.

So every gate proves it bites. Under `<lang>/bad_examples/` sits deliberately broken code, one subdirectory per gated rule class. Fixtures are excluded from normal tooling by native scoping — path filters and config sections, never inline suppressions — so the fixtures themselves stay clean of the hacks they demonstrate. Then `bad_examples/assert.sh` re-runs the tools scoped to the fixtures and asserts that each tool exits nonzero with the expected stable rule IDs. That script is the `negative` phase of `verify.sh`.

The payoff: when a tool stops enforcing a rule, the negative phase fails the build the day it happens, not the year. The gates carry their own regression tests, exactly as good code does.

## What this repository is not

- **Not a framework.** There is no library to install, no CLI to run, no runtime dependency. Templates are copied wholesale into your project and owned by it from then on.
- **Not application scaffolds beyond the example.** Every template implements exactly one canonical domain — warehouse order placement, specified in [CONTRACTS.md](CONTRACTS.md) — chosen because it exercises the layers, ports, state, and error paths the gates need to police. It is a demonstration harness, not a starting point for a product.
- **Not a substitute for review.** Gates catch mechanical violations: style, types, boundary breaches, vacuous tests, leaked secrets, stale lockfiles. They cannot judge whether a design is wise, a name is humane, or a feature is right. That is what reviewers are for — and because the machines absorb everything mechanical, reviewers get to spend their attention entirely on judgment.
