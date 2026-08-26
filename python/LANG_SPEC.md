# Python language specification

This template is the reference implementation of [`docs/CONTRACTS.md`](../docs/CONTRACTS.md)
for Python. Every knob lives in [`pyproject.toml`](pyproject.toml); this document
explains why each knob sits where it does, what it forbids, and where we
deliberately chose not to enforce. Silence here means compliance with the
contract; deviations from the canonical snippets are called out explicitly.

## Philosophy

CI is the style guide ([`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md)). For a coding
agent working in Python this has one concrete consequence: the agent's entire
definition of "done" is `./verify.sh` printing eleven PASS lines. So every
property worth having is expressed mechanically:

- strictness becomes `select = ["ALL"]` plus the smallest defensible ignore list;
- architecture becomes import-linter contracts that fail the build, not an ADR nobody reads;
- honest tests become branch-coverage floors plus property-based generation plus (nightly) mutants;
- trust in the gates themselves becomes `bad_examples/`, fixtures each gate must reject on demand.

Python-specific reality shapes some choices: there is no compiler, so
basedpyright strict mode stands in for compile-time checking; the interpreter
allows anything at runtime, so ruff carries more structural load than its
counterparts in other languages here.

## Toolchain

| Concern | Tool | Pin | Why | Source |
| --- | --- | --- | --- | --- |
| Runtime | CPython | `3.13` (`.python-version`) | current stable line; matches the pinned `python:3.13-slim` image | <https://www.python.org/downloads/> |
| Packages | uv | image-pinned `ghcr.io/astral-sh/uv:0.12.6`; `uv sync --locked` is the only install path | fastest resolver, single lockfile, dev-group support | <https://docs.astral.sh/uv/> |
| Format | ruff format | `>=0.16,<0.17` | formatter is non-configurable-by-design; preview style enabled | <https://docs.astral.sh/ruff/formatter/> |
| Lint | ruff check | `>=0.16,<0.17`; `select=["ALL"]` | one tool, one config, maximal rule surface; exact versions locked in `uv.lock` | <https://docs.astral.sh/ruff/linter/> |
| Types | basedpyright | `>=1.39`; `typeCheckingMode="strict"`, `failOnWarnings=true` | strictest available Python checker; warns-as-errors honors principle 1 | <https://github.com/detachhead/basedpyright> |
| Architecture | import-linter | `>=2.13`; layered + independence + forbidden contracts | executable layering; cycles and boundary breaches fail the build | <https://import-linter.readthedocs.io/> |
| Tests | pytest | `>=9`; addopts `--strict-markers --strict-config -ra` | marker/config typos become errors, not silent skips | <https://docs.pytest.org/en/stable/> |
| Coverage | pytest-cov + coverage.py | `>=7` / locked; `branch=true`, `fail_under=96` | branch coverage catches half-tested conditionals | <https://coverage.readthedocs.io/en/latest/>, <https://github.com/pytest-dev/pytest-cov> |
| Property | hypothesis | locked; `ci` profile: `max_examples=200`, `deadline=None`, derandomize off | example generation finds invariants unit tests never name; profile activates when `CI=true` | <https://hypothesis.readthedocs.io/en/latest/> |
| Dead code | vulture | locked; `--min-confidence 80` + `vulture_whitelist.py` | dynamic call sites make Python dead-code detection heuristic; whitelist keeps it honest | <https://github.com/jendrikseipp/vulture> |
| Security | pip-audit | locked; `--strict` against the lock-exported pin set | audits exactly what the environment installs, fails closed | <https://github.com/pypa/pip-audit> |
| Lock hygiene | uv | `uv lock --check` | proves `uv.lock` still satisfies `pyproject.toml` | <https://docs.astral.sh/uv/reference/cli/#uv-lock> |
| Mutation (config only) | mutmut | `[tool.mutmut] paths_to_mutate=["src"]` | configured now, scheduled never in PR CI — nightly tier only | <https://github.com/boxed/mutmut> |

Dev tools live in `[dependency-groups].dev` (uv's default group), so plain
`uv sync --locked` installs them; no separate test requirements file exists,
which is why the security gate can audit one coherent environment.

## Gate-by-gate walkthrough

`./verify.sh` runs these phases in canonical order, printing one
`GATE <phase>: PASS` line each. Each phase below names the fixture in
[`bad_examples/`](bad_examples/) that proves it bites.

1. **deps** — `uv sync --locked`. Installs the exact lockfile into `.venv`.
   No network-resolved ranges, no global site-packages. Nothing to bite here
   by design: drift is caught by `deps-hygiene`.
2. **format** — `ruff format --check .`. Never rewrites. Fixture:
   `bad_examples/unformatted/unformatted.py` — misaligned braces and spacing;
   scoped check reports it *would be reformatted* and exits nonzero.
3. **lint** — `ruff check .` with `ALL` selected. Fixtures:
   - `too_complex/too_complex.py`: 13-branch router → rejected (`PLR0912`,
     plus `C901`);
   - `insecure/insecure.py`: hardcoded password string (`S105`);
   - `printing/printing.py`: bare `print()` (`T201`);
   - `naive_datetime/naive_datetime.py`: tz-naive `datetime.now()` (`DTZ005`);
   - `todo_comment/todo_comment.py`: untagged, unlinked TODO (`TD003`).
   The negative phase asserts the stable machine-readable codes from ruff's
   JSON output — human formats print names, which are not API.
4. **types** — `basedpyright` over `src` and `tests` in strict mode with
   `failOnWarnings`. Fixture: `type_violation/type_violation.py` — a wrong-type
   argument and two untyped parameters; scoped run reports
   `reportArgumentType` et alia and exits nonzero.
5. **arch** — `lint-imports` enforcing three contracts: layered
   (adapters → application → domain, exhaustive), adapter independence, and
   production-never-imports-tests. Fixture: `arch_violation/arch_violation.py`
   — domain importing an adapter; assert.sh copies it into
   `src/warehouse/domain/` for one run (import-linter analyzes installed
   modules only), watches the layered contract break, then removes it in a trap.
6. **test** — `pytest tests/unit tests/integration -q`. Unit tests cover every
   Money/Quantity/Sku invariant and every Order transition; integration tests
   drive the full use-case pipeline through the in-memory adapters across
   happy, insufficient-stock, declined-payment, and invalid-order paths.
7. **coverage** — full suite under `--cov=warehouse --cov-branch`, with
   `CI=true` exported so hypothesis runs its 200-example `ci` profile.
   `fail_under = 96` (see thresholds). Vacuous tests cannot hold this floor
   while real logic stays untested.
8. **deadcode** — `vulture src vulture_whitelist.py --min-confidence 80`.
   Only `src` is scanned: unused test helpers are noise, unused production
   code is a lie. Fixture: `dead_code/dead_code.py` — a module-level function
   no caller references; probed at confidence 60, where vulture reports
   function-level findings (see trade-off below).
9. **security** — exports the locked pin set (`uv export --no-emit-project`)
   and audits it with `pip-audit --strict --no-deps`. Fails closed: any
   unauditable dependency or known advisory fails the build.
10. **deps-hygiene** — `uv lock --check`. A `pyproject.toml` edit without a
    regenerated lockfile fails here the same day it happens.
11. **negative** — `bash bad_examples/assert.sh`, running every fixture above
    through its gate scoped to the fixture file, asserting nonzero exit plus
    the expected signal. The manifest table at the top of `assert.sh` maps
    fixture → gate → signal; any MISS fails the build.

The optional `mutation` phase prints `GATE mutation: SKIP (nightly tier only)`
unless `VERIFY_TIER=full`, in which case it runs `mutmut run` and parses the
kill score against `MUTATION_FLOOR` (default 70). It is wired for the nightly
`full.yml` tier and intentionally absent from pull-request CI.

## Thresholds

| Threshold | Value | Rationale | Trade-off |
| --- | --- | --- | --- |
| ruff `line-length` | 88 | formatter default; zero config drift | slightly denser than 100; consistent with black ecosystem |
| ruff `max-complexity` (mccabe) | 10 | classic ceiling; forces table-driven designs early | occasional refactor of genuinely branchy parsers |
| pylint `max-args / max-branches / max-statements / max-returns / max-nested-blocks / max-locals` | 5 / 8 / 35 / 6 / 4 / 10 | stricter than defaults; targets agent-generated kitchen sinks | signatures pass bundles of related values instead of loose arg lists |
| pytest `filterwarnings` | `error` | principle 1: no warning survives as a warning | dependency deprecation warnings must be handled, not ignored |
| coverage `branch=true` | on | half-taken conditions are untested logic | more tests needed per conditional |
| coverage measured baseline | **100.00%** (195 stmts, 36 branches, first green run) | reference point for R3 floor | — |
| coverage `fail_under` | **96** (= floor(100 − 4), ≥ 85 floor) | Ruling R3 buffer absorbs small refactors without licensing gaps | new branches need tests within ~4 points of landing |
| hypothesis `ci` profile | 200 examples, deadline off, derandomize off | broad search in CI; wall-clock stability without losing variety | slower CI than 50 examples; local default stays at 50 |
| vulture `min-confidence` | 80 | imports (90%) and unreachable code (100%) flagged; lower confidences whitelist-driven | function-level dead code (60%) is not flagged in production scan — see next row |
| vulture fixture probe confidence | 60 (negative phase only) | proves the tool still detects function-level death | repo gate and fixture probe differ deliberately; documented rather than hidden |
| mutation kill-score floor | 70 (`MUTATION_FLOOR`) | nightly-tier aspiration, tunable before scheduling | unscheduled; not yet load-bearing |
| uv pin | `0.12.6` image tag | reproducible installs byte-for-byte | renovate-style bumps update one Dockerfile line |

## Deliberate non-enforcements

Every entry here is a decision, recorded so silence cannot be mistaken for
oversight. The ignore list in `pyproject.toml` mirrors this table.

- **ty (Astral type checker): excluded until stable.** Promising, but still
  pre-1.0 with a moving rule surface (<https://github.com/astral-sh/ty>).
  basedpyright covers the role today; revisit when ty stabilizes.
- **mypy: passed over.** Slower on this tree and less strict by default;
  basedpyright strict subsumes its value here
  (<https://github.com/python/mypy>).
- **mutmut: configured, unscheduled.** Mutation testing reshapes test-writing
  behavior most when results arrive fast; nightly-only keeps PR CI fast while
  the floor hardens (<https://github.com/boxed/mutmut>). jqwik is n/a for
  Python — hypothesis owns property testing in this ecosystem.
- **CPY001 (copyright notices)** — legal boilerplate is policy, not code
  quality; forcing a header on every generated file buys nothing mechanical.
- **EXE002 (shebang on executable files)** — Windows bind mounts mark every
  file executable regardless of content, so the rule misfires locally; entry
  points are invoked via interpreters throughout this harness.
- **EM101 / EM102 / TRY003 (raise-site message ergonomics)** — domain errors
  here are structured payload classes whose message documents the failure at
  the raise site. Demanding variable indirection (EM101/EM102) or class-level
  messages only (TRY003) adds ceremony without safety; the trio conflicts with
  itself otherwise.
- **D203/D212 vs D211/D213, COM812/ISC001** — intra-family conflicts resolved
  toward D211/D213 and formatter ownership; standard practice, documented for
  completeness.
- **N818 limited to `src/warehouse/domain/errors.py`** — the contract fixes
  error names (`InsufficientStock`, `OrderAlreadyShipped`); the Error-suffix
  convention must not rename them. Scoped to the one file that defines them.
- **import-linter `include_external_packages = true`** — deviates from the
  canonical snippet's `False` because import-linter ≥2 rejects external
  forbidden modules otherwise, and `tests` lives outside the package. Same
  semantics, one required flag.
- **import-linter layered contract uses `containers`** — `exhaustive` is
  unsupported without containers in import-linter ≥2. Layer names became
  relative; semantics identical to the canonical snippet.
- **basedpyright does not list `bad_examples` under exclude** — pyright honors
  exclusion even for command-line files, which would let the type fixture
  pass silently. Include-scoping already keeps fixtures out of the main run.
- **security audits the lock-exported pin set instead of the raw venv** — the
  synced environment contains the local project root, which PyPI cannot audit
  and `--strict` rightly refuses to skip. Exporting fresh from `uv.lock` with
  `--no-emit-project` audits every third-party pin, failing closed.

## Workflows

### Clone and go

1. Copy `python/` wholesale into your repository.
2. Rename the package: move `src/warehouse` to `src/<your_package>` and update
   `name` in `[project]`, `root_package` and the contract module lists under
   `[tool.importlinter]`, and the `--cov=<pkg>` flag in `verify.sh`'s coverage
   phase.
3. Keep `bad_examples/` paired with the `negative` phase; deleting one without
   the other removes the proof that your gates bite.
4. Add your runtime dependencies to `[project.dependencies]`, run `uv lock`,
   commit `uv.lock`. Tools stay in `[dependency-groups].dev`.
5. Regenerate the whitelist only when vulture flags genuinely-used dynamic
   code; each entry gets a reason.

### Hermetic run

```bash
docker compose build python     # official python:3.13-slim + pinned uv only
docker compose run --rm python  # mounts ./python at /workspace, runs verify.sh
docker compose run --rm python lint   # any subset of phases, canonical order
```

Caches (`UV_CACHE_DIR`, `XDG_CACHE_HOME`) point at workspace-relative,
gitignored directories, satisfying the container preamble in CONTRACTS §4 —
nothing leaks outside the workspace or into image layers. Quality tools are
never baked into the image; the `deps` phase installs them from the committed
lockfile on every run.

### Suppression policy

Inline suppressions exist for the rare case where a rule misfires on correct
code. They are loud by convention and enforced by review:

```python
result = legacy_api()  # noqa: S608 — table name comes from a vetted allowlist, not user input
```

Every `# noqa` must carry the specific code AND a trailing justification
sentence naming why the rule does not apply. Bare `# noqa` is treated as gate
tampering and rejected in review. Ruff cannot force justification text
mechanically; the convention is documented here and reviewers are expected to
reject violations. Config-level scoping (per-file-ignores, extend-exclude) is
always preferred over inline suppression because it is visible in one place —
this repository.

## Mechanism analysis

Why each gate changes agent behavior, not just detects after the fact:

- **Lint ALL + warnings-as-errors** removes negotiation. An agent cannot ship
  `print()` debugging, magic booleans, or star-imports because the failure is
  immediate and named; it refactors instead of rationalizing.
- **Strict types with failOnWarnings** moves whole bug classes (None-flow,
  wrong payloads, implicit Any) out of review commentary into red output. The
  agent learns to annotate first, because annotation-last always loses.
- **Executable architecture** converts "don't import adapters from the domain"
  from tribal memory into a failing contract; agents stop guessing boundaries
  because crossing one fails deterministically within seconds.
- **Branch-coverage floors + property tests** attack vacuous testing: a test
  that executes code without constraining it cannot hold 96% branch coverage
  once real logic lands, and randomized examples keep finding the off-by-one
  the happy-path test never generates.
- **Deadcode + security + lock hygiene** close the quiet rot channels: unused
  code accretes, advisories land mid-week, lockfiles drift from manifests.
  Each has a gate whose failure message points at the exact artifact.
- **Negative fixtures** discipline the gates themselves. When a ruff release
  drops or renames a rule, `too_complex` stops being rejected and the
  `negative` phase fails the same day — the toolchain carries its own
  regression tests, so strictness cannot silently decay into mood.
