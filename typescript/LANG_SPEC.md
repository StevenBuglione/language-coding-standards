# TypeScript language specification

This template is a reference implementation of [`docs/CONTRACTS.md`](../docs/CONTRACTS.md)
for TypeScript, at parity with the Python reference. Every knob lives in the
committed configs (`package.json`, `tsconfig.json`, `eslint.config.js`,
`vitest.config.ts`, `knip.json`, `.dependency-cruiser.cjs`,
`stryker.config.json`); this document explains why each knob sits where it
does, what it forbids, and where we deliberately chose not to enforce.
Silence here means compliance with the contract; deviations from the canonical
snippets are called out explicitly.

## Philosophy

CI is the style guide ([`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md)). For a
coding agent working in TypeScript the definition of "done" is `./verify.sh`
printing eleven PASS lines. Every property worth having is therefore expressed
mechanically:

- strictness becomes the full max-strictness tsconfig flag set plus
  typescript-eslint's type-aware bundles — not "we use TypeScript";
- architecture becomes dependency-cruiser rules that fail the build;
- honest tests become coverage floors plus fast-check properties plus
  (nightly) mutants;
- trust in the gates themselves becomes `bad_examples/`, fixtures each gate
  must reject on demand.

TypeScript-specific reality shapes some choices: the compiler already carries
the load basedpyright carries in the Python template, so lint spends its
budget on structure and intent instead of emulating a type checker; and the
ecosystem moves fast enough that every pin below was verified against the
registry on the day this template froze (see Toolchain).

## Toolchain

| Concern                | Tool                             | Pin                                                                                         | Why                                                                                                                      | Source                                                                                                          |
| ---------------------- | -------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------- |
| Runtime                | Node.js                          | `24.x` (`engines: ">=24 <25"` + `.npmrc engine-strict`)                                     | current Active LTS line; matches the pinned `node:24-bookworm` image; corepack still ships in v24 (removed starting v25) | <https://github.com/nodejs/release#release-schedule>, <https://nodejs.org/docs/latest-v24.x/api/corepack.html>  |
| Packages               | pnpm via corepack                | `pnpm@11.24.0` in `packageManager`; lockfile committed; installs always `--frozen-lockfile` | corepack resolves exactly the pinned version from the manifest; frozen installs are the only install path                | <https://pnpm.io/cli/install>                                                                                   |
| Format                 | Prettier                         | `3.9.6`; `printWidth: 100`; check-only in CI                                                | formatter is effectively non-configurable by design; one small config surface                                            | <https://prettier.io/docs/>                                                                                     |
| Lint                   | ESLint                           | `10.9.1` flat config                                                                        | flat config is the only config system of ESLint 10                                                                       | <https://eslint.org/docs/latest/use/configure/>                                                                 |
| Typed lint             | typescript-eslint                | `8.68.0`; `strictTypeChecked` + `stylisticTypeChecked` via `projectService`                 | the type-aware rule bundles are the strictest static analysis TypeScript gets without a SAST                             | <https://typescript-eslint.io/users/configs/>                                                                   |
| Opinions               | eslint-plugin-unicorn / -sonarjs | `73.0.0` / `4.2.0`                                                                          | structural/opinionated rules (member order, boolean names) + cognitive complexity                                        | <https://github.com/sindresorhus/eslint-plugin-unicorn>, <https://github.com/SonarSource/eslint-plugin-sonarjs> |
| Types                  | tsc                              | `typescript@6.0.2`; full flag table below                                                   | the compiler itself is the type gate; `--noEmit` over src+tests                                                          | <https://www.typescriptlang.org/tsconfig/>                                                                      |
| Architecture           | dependency-cruiser               | `18.2.0`; layered rules + no-circular + not-to-dev-dep + no-orphans                         | executable layering anchored at `^src/<layer>`; violations fail the build                                                | <https://dependency-cruiser.github.io/docs/>                                                                    |
| Dead code              | knip                             | `6.32.2`; entry = `src/index.ts` + tests                                                    | unused files/exports/dependencies across the whole project graph                                                         | <https://knip.dev>                                                                                              |
| Tests                  | vitest                           | `4.1.11`                                                                                    | ESM-native, vite-powered; same engine runs tests and coverage                                                            | <https://vitest.dev/>                                                                                           |
| Coverage               | @vitest/coverage-v8              | `4.1.11` (exact peer match); thresholds enforce the floor                                   | v8 provider keeps the coverage run identical to the test run                                                             | <https://vitest.dev/guide/coverage.html>                                                                        |
| Property               | fast-check                       | `4.9.0`                                                                                     | randomized generation with shrinking; ≥2 property tests per CONTRACTS §2                                                 | <https://fast-check.dev>                                                                                        |
| Mutation (config only) | StrykerJS                        | `10.0.0` core + vitest runner; incremental + perTest                                        | configured now, scheduled never in PR CI — nightly tier only                                                             | <https://stryker-mutator.io/docs/stryker-js/introduction/>                                                      |
| Security               | pnpm audit                       | `audit --prod --audit-level high`                                                           | audits what would ship; see non-enforcements for the SAST gap                                                            | <https://pnpm.io/cli/audit>                                                                                     |

All pins were resolved against registry state on 2026-08-26. Dev tools live in
`devDependencies` only — the template has zero runtime dependencies, which is
also why the security gate can audit an empty prod set honestly.

### Why ESLint, not Biome or oxlint

Biome v2 explicitly stops short of compiler-grade type information: its
type-inference layer covers a subset of what typescript-eslint's type-aware
rules compute from the real checker (<https://biomejs.dev/blog/biome-v2/>).
The rules that change agent behavior here — `no-floating-promises`,
`no-misused-promises`, `no-unnecessary-condition`, `switch-exhaustiveness-check`,
`restrict-template-expressions` — need that type information. Roughly 75–85%
of typescript-eslint's typed-rule surface has no Biome equivalent today, and
oxlint's typed support is similarly partial. A maximal-strictness template
cannot be built on a linter that cannot express the strictness. The trade-off,
accepted and recorded: ESLint is slower than the Rust tools, which is why the
gates stay split into independently runnable phases.

### Why Prettier, not oxfmt

oxfmt (from the Oxc project) is still pre-stable beta tooling with a moving
formatting surface (<https://oxc.rs>). A format gate must be boring:
byte-stable output and zero churn between releases. Prettier is the ecosystem
default whose edge cases are documented and settled. Revisit when oxfmt hits
1.0.

### Why vitest, not jest

Jest's ESM story remains transform-heavy and its watch/transform pipeline
duplicates what vite already does for this codebase. Vitest runs the exact
modules the compiler sees (`verbatimModuleSyntax`, no Babel layer), shares one
config with coverage thresholds, and StrykerJS ships a first-party vitest
runner. Jest adds a second build system without adding a capability.

## tsconfig: the full flag table

Every flag below is active (see [`tsconfig.json`](tsconfig.json)); none is
listed for decoration.

| Flag                                    | What it forces                                                                                                                                                                                                                                                               |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `strict`                                | the strict family: strict null checks, functions in classes, bind/call/indirect strictness, `useUnknownInCatchVariables`, `noImplicitAny`                                                                                                                                    |
| `noUncheckedIndexedAccess`              | every index access returns `T \| undefined`; indexing is a branch, not an assumption                                                                                                                                                                                         |
| `exactOptionalPropertyTypes`            | optional properties do not accept explicit `undefined` unless declared; option bags are honest                                                                                                                                                                               |
| `verbatimModuleSyntax`                  | import/export forms survive verbatim to emit; type-only imports must say `type`                                                                                                                                                                                              |
| `isolatedModules`                       | every file is a module a transpiler could handle alone; no cross-file const enum tricks                                                                                                                                                                                      |
| `moduleDetection: "force"`              | every file is treated as a module regardless of imports                                                                                                                                                                                                                      |
| `noImplicitOverride`                    | overridden members must say `override`; accidental shadowing fails the build                                                                                                                                                                                                 |
| `noFallthroughCasesInSwitch`            | switch fallthrough is always a bug, never a style                                                                                                                                                                                                                            |
| `noImplicitReturns`                     | every code path returns explicitly; implicit `undefined` leaks fail                                                                                                                                                                                                          |
| `noUnusedLocals` / `noUnusedParameters` | dead bindings are compile errors, not lint opinions                                                                                                                                                                                                                          |
| `noPropertyAccessFromIndexSignature`    | dot access works only for declared properties; index signatures require brackets                                                                                                                                                                                             |
| `noUncheckedSideEffectImports`          | importing a module with no exports fails; side-effect imports must resolve                                                                                                                                                                                                   |
| `strictBuiltinIteratorReturn`           | iterator `next()` results narrow `undefined` correctly under downlevel iteration                                                                                                                                                                                             |
| `erasableSyntaxOnly`                    | only syntax that strips away compiles: no enums, no namespaces, no parameter properties — the source stays valid to strip-types/Bun/esbuild verbatim                                                                                                                         |
| `skipLibCheck: false`                   | declaration files are type-checked too — ours and the pinned toolchain's. This is the maximal choice and passes today because every dep is pinned; if a future dependency ships broken typings, flip to `true` and record it here as an ecosystem concession, never silently |

`moduleResolution: "bundler"` matches how the template actually executes
(vitest resolves modules like a bundler). `types: []` disables automatic
`@types/*` injection; `@types/node` is pinned explicitly because the domain
uses `crypto.randomUUID`.

## Gate-by-gate walkthrough

`./verify.sh` runs these phases in canonical order, printing one
`GATE <phase>: PASS` line each. Each phase below names the fixture in
[`bad_examples/`](bad_examples/) that proves it bites.

1. **deps** — `corepack enable pnpm` then `pnpm install --frozen-lockfile`.
   Installs the exact lockfile into `node_modules` inside the workspace mount.
   Corepack availability is established unconditionally at startup so any
   phase subset works in a fresh container (CONTRACTS §5 splits phases across
   jobs). Drift is caught by deps-hygiene, not here.
2. **format** — `prettier --check .`. Never rewrites. Fixture:
   `bad_examples/unformatted/unformatted.ts` — misaligned braces and spacing;
   the probe bypasses `.prettierignore` via `--ignore-path /dev/null` and
   reports _Code style issues found_, exiting nonzero.
3. **lint** — `eslint . --report-unused-disable-directives`. Fixtures:
   - `too_complex/too_complex.ts`: 17-arm router → rejected (`complexity`);
   - `insecure/insecure.ts`: `eval()` → rejected (custom `no-restricted-syntax`
     message `forbidden: eval()`);
   - `naive_datetime/naive_datetime.ts`: `new Date()` → rejected (custom ban
     `forbidden: new Date()` — forcing explicit clock injection);
   - `printing/printing.ts`: bare `console.log` (`no-console`);
   - `todo_comment/todo_comment.ts`: untracked work note (`no-warning-comments`).
     The negative phase asserts stable machine-readable signals from
     eslint's `--format json` output (ruleId/message), not human formats.
4. **types** — `tsc --noEmit` over `src`, `tests`, `vitest.config.ts` with the
   flag table above. Fixture: `type_violation/type_violation.ts` — scoped run
   through its own `tsconfig.json` reports `error TS2322` and exits nonzero.
5. **arch** — `depcruise src` enforcing: `domain-no-outbound` (domain never
   imports application/adapters), `application-no-adapters`, `no-circular`,
   `not-to-dev-dep`, `no-orphans`. Fixture:
   `arch_violation/arch_violation.ts` — assert.sh copies it into
   `src/domain/` for one run (the layer rules anchor at `^src/`), watches
   `domain-no-outbound` fire, removes it in a trap.
6. **test** — `vitest run`. Unit tests cover every Money/Quantity/Sku
   invariant and every Order transition; integration tests drive the full
   pipeline through the public entry point (`src/index.ts`) across happy,
   insufficient-stock, declined-payment, and invalid-order paths; property
   tests generate Money arithmetic pairs and random valid line sets.
7. **coverage** — `vitest run --coverage` with thresholds enforcing the R3
   floor (see Thresholds). Vacuous tests cannot hold the floor while real
   logic stays untested.
8. **deadcode** — `knip` over entries `src/index.ts` +
   `tests/**/*.test.ts`, proven on both of its layers by the negative
   phase: the `dead_code/dead_code.ts` copy surfaces as an unused FILE, and
   a dead export appended to the reachable module `src/domain/sku.ts`
   surfaces as an unused EXPORT. The export-level proof holds only because
   `src/index.ts` forwards every symbol by explicit name — an
   `export *` barrel at the entry file would be exempt from knip's analysis
   and could mask dead exports forever, so barrels are banned there by
   design (see non-enforcements).
9. **security** — `pnpm audit --prod --audit-level high`. The template ships
   zero runtime dependencies, so the audited set is empty by construction;
   any added runtime dependency enters the audit automatically. See
   non-enforcements for the SAST gap this gate does not pretend to close.
10. **deps-hygiene** — re-runs `pnpm install --frozen-lockfile` and proves
    idempotence by comparing the sha256 of `pnpm-lock.yaml` before and after:
    a frozen install that mutates the lockfile fails, and manifest drift fails
    the install itself. See deviations for why this is a hash guard rather
    than a git-based guard.
11. **negative** — `bash bad_examples/assert.sh`, running every fixture above
    through its gate scoped to the fixture file, asserting nonzero exit plus
    the expected signal. The manifest table at the top of `assert.sh` maps
    fixture → gate → signal; any MISS fails the build.

The optional `mutation` phase prints `GATE mutation: SKIP (nightly tier only)`
unless `VERIFY_TIER=full`, in which case it runs `stryker run`; StrykerJS
enforces its own `thresholds.break = 70` from `stryker.config.json`, so a weak
suite exits nonzero and fails the gate without output parsing. It is wired for
the nightly `full.yml` tier and intentionally absent from pull-request CI.

## Thresholds

| Threshold                       | Value                                                                                                                                                                    | Rationale                                                                                                      | Trade-off                                                                                     |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| prettier `printWidth`           | 100                                                                                                                                                                      | brief-specified width; wider than Python's 88 because TS idioms (unions, long interface names) wrap poorly     | denser lines than prettier's default 80                                                       |
| eslint `complexity`             | 15                                                                                                                                                                       | brief cap; cyclomatic ceiling per function                                                                     | occasional refactor of genuinely branchy parsers                                              |
| sonarjs `cognitive-complexity`  | 15                                                                                                                                                                       | complements cyclomatic with nesting/load penalties                                                             | two complexity lenses to satisfy                                                              |
| eslint `max-depth`              | 4                                                                                                                                                                        | nesting beyond four reads as state-machine denial                                                              | deep parsers need early returns                                                               |
| eslint `max-lines-per-function` | 120 (skipBlankLines+skipComments)                                                                                                                                        | whole-function comprehension in one screenful                                                                  | large table literals may need extraction                                                      |
| eslint `max-statements`         | 25 (ignoreTopLevelFunctions)                                                                                                                                             | module-level wiring is exempt; logic functions stay small                                                      | —                                                                                             |
| eslint `max-params`             | 4                                                                                                                                                                        | signatures pass bundles of related values instead of loose arg lists                                           | ports take (sku, quantity) style pairs comfortably                                            |
| coverage measured baseline      | **97.91% lines / 97.93% stmts / 100% funcs / 93.47% branches** (95/97 stmts, 43/46 branches, first fully green run; `src/index.ts` excluded as a pure re-export surface) | reference point for the R3 floor                                                                               | remaining gaps are two defensive branches (non-domain rethrow, unreachable-empty-lines guard) |
| coverage floor (R3)             | **lines 93, statements 93, functions 96, branches 89** (= floor(measured − 4); lines well above the 85 minimum)                                                          | buffer absorbs small refactors without licensing gaps                                                          | new branches need tests within ~4 points of landing                                           |
| fast-check runs per property    | default 100 (library default; deterministic counterexample shrinking on failure)                                                                                         | parity-of-effort with hypothesis' local profile; CI=true profile machinery dropped as nothing consumes it here | fewer examples than python's nightly-style ci profile                                         |
| stryker `thresholds.break`      | 70                                                                                                                                                                       | nightly aspiration, tunable before scheduling                                                                  | unscheduled; not yet load-bearing                                                             |
| pnpm pin                        | `pnpm@11.24.0` via `packageManager`                                                                                                                                      | reproducible installs byte-for-byte; corepack downloads exactly this version                                   | renovate-style bumps update one package.json field                                            |

## Deliberate non-enforcements

Every entry here is a decision, recorded so silence cannot be mistaken for
oversight. Config-level relaxations mirror this table; inline suppressions do
not exist anywhere in `src/` or `tests/`.

- **No free TypeScript SAST.** `eslint-plugin-security` is unmaintained, and
  no mainstream free SAST covers TS idiomatically today. Instead of a fake
  signal, two custom `no-restricted-syntax` bans carry the security-shaped
  load this template needs: `eval()` and the no-arg `new Date()` ambient-clock
  read (forcing explicit time injection). Both carry stable `forbidden:`
  messages asserted by the negative phase. Roadmap: Socket.dev manifests +
  semgrep when a free tier fits hermetic CI — recorded here, not silently
  skipped.
- **unicorn/name-replacements off.** The rule rewrites ubiquitous-language
  names ("repository" → "repo", "inventory" → "stock"). CONTRACTS §2 canonically
  names `OrderRepository` and the adapters layer; domain vocabulary wins over
  word substitutions.
- **sonarjs/no-duplicate-string off, tests only.** Repeated assertion literals
  ("USD", sku codes) are test data, not duplication debt. Scoped by config
  segment to `tests/**/*.test.ts`, visible in one place.
- **JSDoc on every exported symbol is documented policy, not a gate.** v0
  ships JSDoc everywhere in `src/` but no doc-enforcement gate exists in the
  toolchain; adding `eslint-plugin-jsdoc`'s completeness rules is roadmap.
  Reviewers reject missing docs; the machine does not yet.
- **Public API freeze enforcement is roadmap.** knip proves the export graph
  is reachable, but nothing yet freezes the public signature surface
  (api-extractor baselines would); noted here rather than claimed.
- **Mutation testing: configured, unscheduled.** Nightly-only keeps PR CI fast
  while the suite hardens (same stance as the Python template's mutmut).
- **eslint.config.js is plain JavaScript.** A TS config file would require
  jiti or native strip-types just to parse — a dependency and a Node-version
  coupling the toolchain does not need. Documented choice per the toolchain
  brief's escape hatch.
- **switch-exhaustiveness-check comes from typescript-eslint**, not a separate
  plugin: the rule lives in the typescript-eslint bundle, so the brief's
  "plugin if not in core" clause is satisfied without a new dependency.
- **node:24-bookworm, not -slim.** bookworm-slim ships without git; keeping
  git in the image preserves parity between local compose runs and CI
  containers where the checkout is present. One base-image tag, documented.
- **Deps-hygiene uses a hash guard, not git.** The compose mount exposes
  `typescript/` without `.git` metadata, so `git diff --exit-code` cannot run
  inside the container (and CRLF normalization makes whole-tree porcelain
  checks platform-flaky anyway). sha256-before/after on `pnpm-lock.yaml`
  proves the same invariant — byte-exact idempotence — deterministically on
  every platform. This deviates from the tasking brief's git-based sketch.
- **Coverage excludes `src/index.ts`.** It is a pure re-export surface with no
  executable statements; measuring it only produces a misleading 0% row.
- **Money tightens integer checking to `Number.isSafeInteger`.** Python ints
  are arbitrary precision; JS numbers are not. Amounts beyond
  `Number.MAX_SAFE_INTEGER` raise `InvalidOrder` — an honest adaptation of
  "integer minor units" to the platform.
- **Currency validation is shape-level, not a live ISO-4217 table.** The
  `/^[A-Z]{3}$/` pattern accepts any three uppercase letters — including
  codes that merely look valid and ISO-4217's own `XXX` placeholder ("no
  currency"). A maintained currency-code table is a data dependency the
  domain does not need for this harness; tighten it only if a project
  actually settles in ambiguous codes.
- **Order status getter is named `state`.** A public `status` accessor cannot
  coexist with the private `status` field in one class; the state-machine
  semantics are unchanged.
- **`src/index.ts` bans `export *` barrels by design** (not a lint rule; a
  reviewed convention stated here and enforced by review). knip exempts the
  entry file's own exports, so a wildcard barrel would forward any future
  dead export sight unseen and the unused-export probe could never fire.
  Every re-export is explicit; adding a symbol to the public surface is a
  one-line, reviewable act.
- **no-orphans excludes `src/application/ports.ts`.** It is a pure type-only
  contract module, and dependency-cruiser does not record `import type`
  edges, so it can never show an incoming dependency — flagging it would be
  a permanent false positive (this surfaced when the entry moved from
  wildcard barrels to explicit named re-exports). Extend the exclusion list
  in `.dependency-cruiser.cjs` only for other genuinely type-only files;
  runtime code must never hide behind it.
- **package.json scripts mirror the phases; verify.sh stays canonical.**
  Every phase has a same-named script (`deps`, `format`, ..., `negative`,
  plus `mutation`) for direct developer invocation, but verify.sh remains
  the sole gate entrypoint: only it sets up corepack unconditionally,
  enforces canonical ordering, prints the GATE contract lines, and adds the
  deps-hygiene hash guard (the bare `deps-hygiene` script is just the frozen
  install).
- **fast-check replaces hypothesis' CI profile machinery.** No env-conditional
  profile: defaults run identically everywhere; the `CI=true` export the
  Python template uses for hypothesis is dropped because nothing consumes it.

## Workflows

### Clone and go

1. Copy `typescript/` wholesale into your repository.
2. Rename the package in `package.json`; if your layout differs from
   `src/{domain,application,adapters}`, update the layer regexes in
   `.dependency-cruiser.cjs`, `knip.json` globs, and `stryker.config.json`'s
   `mutate` list to match.
3. Keep `bad_examples/` paired with the `negative` phase; deleting one without
   the other removes the proof that your gates bite.
4. Add runtime dependencies with `pnpm add`, commit `pnpm-lock.yaml`. Tools
   stay devDependencies; installs are always `--frozen-lockfile`.
5. Regenerate the coverage baseline only after deliberate refactors: measure,
   set floors to measured − 4 (lines ≥ 85), record both numbers above.

### Hermetic run

```bash
docker compose build typescript     # official node:24-bookworm + corepack only
docker compose run --rm typescript  # mounts ./typescript at /workspace, runs verify.sh
docker compose run --rm typescript lint   # any subset of phases, canonical order
```

Caches point at workspace-relative, gitignored directories
(`npm_config_store_dir=/workspace/.pnpm-store`, `XDG_CACHE_HOME=/workspace/.cache`),
satisfying the container preamble in CONTRACTS §4 — nothing leaks outside the
workspace or into image layers. Quality tools are never baked into the image;
the `deps` phase installs them from the committed lockfile on every run.

### Suppression policy

Inline suppressions exist for the rare case where a rule misfires on correct
code. They are loud by convention and enforced by review:

```ts
// eslint-disable-next-line no-console -- CLI entry point; logging IS the product here
main(process.argv);
```

Every disable must carry the specific rule AND a trailing justification
naming why the rule does not apply. Bare disables are treated as gate
tampering and rejected in review. `--report-unused-disable-directives` makes
every stale suppression a lint error, so suppressions cannot outlive their
justification. Config-level scoping (per-path segments in `eslint.config.js`)
is always preferred over inline suppression because it is visible in one
place — this repository.

## Mechanism analysis

Why each gate changes agent behavior, not just detects after the fact:

- **Max-strictness tsconfig + typed lint** moves whole bug classes
  (null-flow, floating promises, impossible states) out of review commentary
  into red output. The agent learns to model results as discriminated unions
  first, because exception-last architectures keep tripping
  `no-floating-promises` and friends.
- **erasableSyntaxOnly** quietly bans enums and parameter properties, pushing
  agents toward plain unions and explicit fields — the shapes that transpile
  identically everywhere.
- **Executable architecture** converts "don't import adapters from the
  domain" from tribal memory into a failing contract within seconds; the
  layered rules anchor at path level, so a violation cannot hide behind a
  barrel file.
- **Coverage floors + property tests** attack vacuous testing: a test that
  executes code without constraining it cannot hold the floor once real logic
  lands, and fast-check's shrinking hands back minimal counterexamples — the
  safe-integer overflow in `times` was found by exactly this loop during
  bring-up.
- **knip + audit + hash-guarded lockfile hygiene** close the quiet rot
  channels: dead exports accrete, advisories land mid-week, lockfiles drift
  from manifests. Each has a gate whose failure points at the exact artifact.
- **Negative fixtures** discipline the gates themselves. When an ESLint major
  drops a rule or dependency-cruiser renames a schema property (both happened
  during this template's construction), the negative phase fails the same day
  — the toolchain carries its own regression tests, so strictness cannot
  silently decay into mood.
