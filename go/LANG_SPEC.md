# Go language specification

This template is a reference implementation of [`docs/CONTRACTS.md`](../docs/CONTRACTS.md)
for Go, alongside the Python template. Every knob lives in
[`.golangci.yaml`](.golangci.yaml), [`verify.sh`](verify.sh), and the
[`Dockerfile`](Dockerfile); this document explains why each knob sits where it
does, what it forbids, and where we deliberately chose not to enforce. Silence
here means compliance with the contract; deviations are called out explicitly.

## Philosophy

CI is the style guide ([`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md)). For a coding
agent working in Go this has one concrete consequence: the agent's entire
definition of "done" is `./verify.sh` printing eleven PASS lines. So every
property worth having is expressed mechanically:

- strictness becomes an explicit linter roster plus tight complexity ceilings,
  not "we follow the style guide";
- architecture becomes `depguard` rules that fail the build, not an ADR nobody reads;
- honest tests become statement-coverage floors plus table-driven invariant suites;
- trust in the gates themselves becomes `bad_examples/`, fixtures each gate
  must reject on demand.

Go-specific reality shapes some choices: there **is** a compiler, so the types
gate leans on `go build`/`go vet` instead of standing up a checker; the
language's culture already carries strong idioms (`errors.Is/As`, `%w`
wrapping, comma-ok absence), so the lint phase enforces the idioms mechanically
with errorlint/wrapcheck/errorlint-adjacent rules rather than re-teaching them.

Style references this template encodes as gates: the [Go Code Review
Comments](https://go.dev/wiki/CodeReviewComments), the [Uber Go Style
Guide](https://github.com/uber-go/guide/blob/master/style.md), and the
[Google Go Style Guide](https://google.github.io/styleguide/go/).

## Toolchain

| Concern | Tool | Pin | Why | Source |
| --- | --- | --- | --- | --- |
| Compiler | Go toolchain | `go 1.26` in `go.mod`; compiler pinned BY IMAGE TAG `golang:1.26-bookworm` | Swift-style pinning: the image tag IS the toolchain; `GOTOOLCHAIN=local` makes any silent toolchain download a hard failure | <https://go.dev/doc/toolchain>, <https://hub.docker.com/_/golang> |
| Format | gofumpt (+ gci import ordering) via `golangci-lint fmt` | golangci-lint `v2.13.1` | check-only formatting with one config file and one binary | <https://golangci-lint.run/docs/configuration/file/> |
| Lint | golangci-lint v2 | `v2.13.1` (exact minor pinned in `verify.sh`) | v2 schema (`version: "2"`, separate `formatters:` section); roster documented below | <https://golangci-lint.run/docs/linters/>, <https://golangci-lint.run/docs/product/migration-v1-to-v2/> |
| Types | `go build ./... && go vet ./...` | image-pinned compiler | the compiler is the typechecker; vet adds printf/struct-tag/shadow-class findings | <https://pkg.go.dev/cmd/go> |
| Architecture | depguard (plus the internal/ boundary the compiler enforces for free) | same golangci pin | executable layer map; nested-module trick keeps fixtures out by construction | <https://golangci-lint.run/docs/linters/#depguard> |
| Tests | stdlib `testing` only, table-driven | none to install | fakes-over-mocks; see Deliberate deviations | <https://go.dev/doc/tutorial/add-a-test> |
| Coverage | `go test -coverprofile` + `go tool cover -func` awk gate | floor 92 (R3 rule) | total-statement gate parsed from tooling output, not eyeballed | <https://pkg.go.dev/cmd/cover> |
| Property | table-driven invariant suites (2 required) | — | honest stand-in; see Deliberate deviations | — |
| Dead code | `golang.org/x/tools/cmd/deadcode@v0.49.0 -test ./...` + the `unused` default linter | exact version pinned in `verify.sh` | call-graph reachability over `./...` rooted at real mains and tests | <https://pkg.go.dev/golang.org/x/tools/cmd/deadcode> |
| Security | govulncheck `@v1.7.0` (blocking) + gosec in lint | exact version pinned in `verify.sh` | call-graph reachability means only vulnerabilities your code can actually reach fail the build; see Mechanism analysis | <https://go.dev/blog/vuln>, <https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck> |
| Deps hygiene | `go mod tidy -diff && go mod verify` | image-pinned go command | tidy proves go.mod matches the imports; verify proves the module cache checksums | <https://go.dev/ref/mod> |
| Mutation | configured-not-wired: gremlins roadmap | unscheduled | see Deliberate non-enforcements | <https://github.com/go-gremlins/gremlins> |

### Install strategy and supply-chain tradeoff

Tools install fresh on every run during `deps` — nothing quality-related is
baked into the image (CONTRACTS §6):

- **golangci-lint**: the project's official `install.sh`, invoked at an exact
  tag (`v2.13.1`), installing a released binary into `$GOPATH/bin`.
- **deadcode, govulncheck**: `go install <path>@<exact-version>`, built from
  source through the checksum-verified module proxy (`go.sum`/GONOSUMDB
  machinery applies even though this template itself has zero dependencies).

We verified that `go tool` directives (the `tool` directive in go.mod, stable
since Go 1.24) would work for all three tools, but chose NOT to use them here:
the parent module has zero runtime dependencies, and routing dev tools through
go.mod would either force a `tools.go`-style import hack or put tool versions
into the very lockfile whose freshness the deps-hygiene gate proves for
*library* consumers of the template. Pinned install commands keep the
template's own dependency surface empty and make every tool version grep-able
in exactly one file. The tradeoff is explicit: install-script downloads trust
GitHub releases (TLS + tag pinning) instead of the module proxy's checksum
verification; the exact pins in `verify.sh` are the audit point either way.

### Why the compiler is pinned by the Docker image tag

Maven/uv-style declarative pinning maps onto Go imperfectly: go.mod declares
the *language version*, but the actual compiler arrives with the toolchain.
Since Go 1.21 the `go` command auto-downloads whatever toolchain go.mod asks
for — convenient, fatal for reproducibility. This template adopts the
Swift-style answer: the container image tag is the toolchain pin, and
`GOTOOLCHAIN=local` (set in both the Dockerfile and verify.sh) turns any
attempt to silently download another toolchain into an immediate failure.
Tradeoff: bumping the Go version means rebuilding/pinning a new image tag
rather than editing one go.mod line — we consider a visible one-line image
bump a feature, because it cannot happen by accident inside someone else's
laptop cache.

## Gate-by-gate walkthrough

`./verify.sh` runs these phases in canonical order, printing one
`GATE <phase>: PASS` line each. Each phase names its proving fixture in
[`bad_examples/`](bad_examples/) where one exists.

1. **deps** — `go mod download` plus pinned installs of golangci-lint
   (official install.sh), deadcode, and govulncheck (`go install @pin`).
   Every step fails explicitly; a half-installed toolchain must never
   surface later as a missing-command error in an unrelated gate.
2. **format** — `golangci-lint fmt --diff cmd internal`. Check-only. Scoped
   to explicit dirs because `fmt` walks directories directly and would
   otherwise reach into `bad_examples/`, which must stay excluded from main
   gates by construction. Fixture:
   `bad_examples/unformatted/unformatted.go` — spacing/brace violations;
   scoped check emits a unified diff and exits nonzero.
3. **lint** — `golangci-lint run ./...`, warnings are errors, issue caps
   disabled (`max-issues-per-linter: 0`). Roster beyond the default five:
   containedctx, contextcheck, cyclop (≤10), depguard, errorlint, exhaustive
   (`default-signifies-exhaustive: false`), exhaustruct_v5 (domain structs +
   PlaceOrderResult must have fully-named literals), forbidigo (print/clock
   bans), funlen (60 lines / 40 statements), gocognit (≤15), gosec, godot,
   ireturn (stdlib/error/empty/anon allowed), misspell, nestif (≤4), noctx,
   nolintlint (see Suppression policy), prealloc, revive (explicit curated
   rule list), sloglint (no-global, context-only), unconvert, unparam,
   wastedassign, whitespace, wrapcheck. Plus a TODO/FIXME ban implemented as
   a grep step INSIDE this phase (see Deliberate non-enforcements). Fixtures:
   too_complex (cyclop), dead_code (unused), insecure (G101), printing +
   naive_datetime (forbidigo), todo_comment (grep ban).
4. **types** — `go build ./... && go vet ./...`. Fixture:
   `bad_examples/type_violation/type_violation.go` — genuine compile error;
   the probe asserts `go build` fails with `cannot use`.
5. **arch** — `golangci-lint run --default=none -E depguard ./...`: a visibly
   named single-linter pass owning the boundary contract (the full lint pass
   also runs depguard; this one is the architecture gate's home address).
   The layer map lives in `.golangci.yaml` under `depguard.rules`:

   | Layer | May import | Must never import |
   | --- | --- | --- |
   | domain | stdlib | application, adapters |
   | application | stdlib, domain | adapters |
   | adapters | stdlib, application, domain | sibling adapter packages |

   Go additionally enforces the strongest boundary natively: `internal/`
   packages are importable only within their module, so foreign modules fail
   compilation before any linter runs. Fixture:
   `bad_examples/arch_violation/arch_violation.go` — copied into
   `internal/domain/` for one depguard-scoped run (the nested-module trick
   makes the copy necessary AND keeps production scoping clean), removed in
   a trap; expected signal `(depguard)`.
6. **test** — `go test -race -shuffle=on -count=1 ./...`. Race detector on
   every run; shuffle order proves no inter-test coupling; count=1 defeats
   result caching. Tests live next to sources (Go convention). The two
   required invariant suites are TestMoneyAdditionIsCommutative and
   TestOrderTotalEqualsSumOfLineTotals — see Deliberate deviations for why
   they are tables, not hypothesis/fast-check.
7. **coverage** — `go test -race -coverprofile -covermode=atomic
   -coverpkg=./internal/... ./...`, then the `total:` line of `go tool cover
   -func` is parsed and floored. `-coverpkg=./internal/...` makes every test
   binary instrument the whole internal tree so the application-level
   integration test earns credit for driving the adapters; `cmd/` stays out
   of the measured scope as thin wiring. Floor: 92 (R3 rule, see Thresholds).
8. **deadcode** — `deadcode -test ./...`: call-graph reachability from real
   entry points, with `-test` counting test-reachable functions as live
   (this module is a library-style pipeline exercised through its tests plus
   one demo main). The `unused` default linter covers the unexported side.
   Fixture: `bad_examples/dead_code/dead_code.go` probed via the unused
   linter (`is unused`).
9. **security** — `govulncheck ./...`, blocking. See Mechanism analysis for
   why call-graph reachability beats pattern scanning here. gosec rides in
   lint (G101 hardcoded credentials proven by fixture).
10. **deps-hygiene** — `go mod tidy -diff && go mod verify`. An edited
    go.mod without regenerated state fails immediately; module cache
    checksums are verified against the sum database records.
11. **negative** — `bash bad_examples/assert.sh` runs all nine fixtures
    through their gates scoped to the fixture package, asserting nonzero exit
    plus the expected stable signal. Text output colors are disabled in the
    config so `(lintername)` suffixes stay grep-stable.

The optional `mutation` phase prints `GATE mutation: SKIP (nightly tier
only)` unless `VERIFY_TIER=full`.

## Thresholds

| Threshold | Value | Rationale | Trade-off |
| --- | --- | --- | --- |
| cyclop `max-complexity` | 10 | classic ceiling; forces table-driven designs early | occasional refactor of genuinely branchy parsers |
| gocognit `min-complexity` | 15 | cognitive load ceiling above cyclop's structural one; catches deep boolean nesting that cyclop misses | two complexity lenses to keep honest |
| funlen | 60 lines / 40 statements | targets agent-generated kitchen sinks | long tables need subtests |
| nestif `min-complexity` | 4 | flat guards over pyramids | occasionally forces early returns mid-function |
| coverage measured baseline | **96.0%** of statements across `./internal/...` (first green run) | reference point for R3 floor | remaining 4% are provably-unreachable defensive branches — see below |
| coverage floor | **92** (= floor(96 − 4), ≥ 80 floor) | R3 buffer absorbs small refactors without licensing gaps | new branches need tests within ~4 points of landing |
| uncovered-by-construction | Label's closed-enum tail return; NewOrderID's crypto/rand failure branch; Order.Total's propagate-error branches; MustOrderLine panic guard (partially reachable) | defensive code behind injected randomness or a closed enum cannot be exercised without lying in tests | accepted 4%; revisited if the domain grows injectable failure modes |
| exhaustive `default-signifies-exhaustive` | false | a default case must not become a loophole for forgetting new enum members | adding a state forces touching every switch |
| exhaustruct_v5 scope | domain structs + application.PlaceOrderResult | field completeness is the contract where values ARE the data; wiring structs stay free-form | new domain structs demand complete literals everywhere |
| TODO/FIXME grep scope | `internal` + `cmd` only | unfinished-work markers rot silently; bad_examples needs markers for its own fixture | none — production scope is exactly what should be clean |

## Deliberate non-enforcements and deviations

Every entry here is a decision, recorded so silence cannot be mistaken for
oversight.

- **No property-based framework — accepted gap vs hypothesis/fast-check.**
  Go's ecosystem has no standard property-testing library (go-checkup
  candidates like gopter are unmaintained; testing/quick cannot generate
  structured domain values well). Forcing one would violate the
  stdlib-only stance this template takes elsewhere. Instead CONTRACTS' two
  required property tests ship as table-driven invariant suites with
  deterministic seeded generation (fixed boundaries × pseudo-random pairs):
  Money addition commutativity and Order-total-equals-sum-of-line-totals.
  This finds fewer corner cases than hypothesis would; the gap is recorded
  rather than hidden, and mutation testing remains the roadmap item that
  compensates most directly.
- **fakes-over-mocks — deviation from any uber-go/mock mention.** The
  canonical design's InMemory/Fake adapters ARE the doubles; introducing
  mockgen/testify would add reflection-generated indirection around code we
  already possess. (mockgen itself was archived by golang in 2023 and lives
  on as the community uber fork — unnecessary here.) No mocking framework
  appears anywhere in this template.
- **maintidx, gocyclo: skipped** — duplicate lenses over the same code with
  cyclop+gocognit already enforcing structure; three complexity tools buy
  noise, not safety. **NilAway: not bundleable** as a golangci plugin in the
  pinned distribution; the compiler plus exhaustive checks carry the nil-flow
  load for this zero-pointer-magic domain.
- **TODO/FIXME ban via grep, not a linter.** No native Go linter carries an
  unfinished-work-marker rule cleanly (godox exists but its matching is
  keyword-list based and duplicates what one auditable grep line does). The
  ban therefore lives INSIDE the lint phase as a grep over `internal` and
  `cmd`, with the fixture probe asserting the grep still bites. Honest about
  the mechanism: it is a grep, and it is gated.
- **depguard exempts `_test.go`.** Co-located integration tests wire adapter
  doubles into the use case — importing adapters from
  `internal/application/*_test.go` is normal Go practice. Production files
  remain fully guarded, proven by the arch fixture which is NOT exempted.
  Python avoids this only because its tests live outside the package tree;
  Go co-location (mandated by ecosystem convention) forces the choice into
  the open.
- **forbidigo exemptions are path-scoped, per-pattern impossible.** forbidigo
  bans apply per-path, not per-pattern-per-path, so `cmd/` is exempt from
  BOTH print and clock bans, and clock.go likewise. Neither location abuses
  the other's exemption (cmd never reads the clock; clock.go never prints),
  and the negative fixtures prove both bans bite outside those paths.
- **gofumpt settings pin `module-path: warehouse`.** Without it, the
  lint-side formatter check runs with an empty module path, classifies
  warehouse/* imports as standard library, and demands they merge into the
  first import group — diverging from the fmt-side behavior, which resolves
  the module path from go.mod. One config line keeps both sides identical.
- **coverage measures `./internal/...`, not `./...`.** cmd/warehouse is a
  demo main whose statements exist to be read, not executed by tests;
  measuring it would tax the floor for wiring. The `-coverpkg` flag keeps
  cross-package credit honest so the integration test still counts toward
  adapter coverage.
- **mutation: configured-not-wired.** gremlins (<https://github.com/go-gremlins/gremlins>)
  is the only credible Go mutator and is still 0.x. A permanently red
  nightly tier teaches people to ignore red, so the phase skips LOUDLY on
  every tier until gremlins stabilizes; the roadmap comment in verify.sh
  names the replacement point precisely.
- **deadcode runs with `-test`.** Functions reachable only from tests count
  as alive. Rationale: this module is library-shaped; its public API is
  exercised through tests, and flagging test-driven API as dead would push
  authors toward unreachable demo mains instead.

## Workflows

### Clone and go

1. Copy `go/` wholesale into your repository.
2. Rename the module: change `module warehouse` in `go.mod`, rewrite the
   `prefix(warehouse)` gci section and `warehouse/internal/...` depguard /
   exhaustruct patterns in `.golangci.yaml`, update import paths, and adjust
   `-coverpkg=./internal/...` if your layout differs.
3. Keep `bad_examples/` paired with the `negative` phase; deleting one
   without the other removes the proof that your gates bite.
4. Bump the tool versions together in `verify.sh` (`GOLANGCI_LINT_VERSION`,
   `DEADCODE_VERSION`, `GOVULNCHECK_VERSION`).
5. Re-measure coverage after your first green run and reset
   `COVERAGE_FLOOR` per the R3 rule; record the baseline in Thresholds.

### Hermetic run

```bash
docker compose build go          # official golang:1.26-bookworm only
docker compose run --rm go       # mounts ./go at /workspace, runs verify.sh
docker compose run --rm go lint  # any subset of phases, canonical order
```

Caches (`GOPATH`, `GOCACHE`, `GOMODCACHE`, `GOLANGCI_LINT_CACHE`,
`XDG_CACHE_HOME`) point at workspace-relative, gitignored directories per
CONTRACTS §4 — nothing leaks outside the workspace or into image layers, and
reruns stay warm. Quality tools install during `deps` on every cold run at
the versions pinned in verify.sh.

### Suppression policy

Inline suppressions exist for the rare case where a rule misfires on correct
code. They are mechanically policed by nolintlint
(`require-explanation: true`, `require-specific: true`, `allow-unused:
false`): every directive must name the exact linter AND carry a reason, and
an unused directive fails the build like any stale code:

```go
_, _ = fmt.Fprintf(os.Stdout, "...") //nolint:errcheck // demo stdout report; a failed print must not fail the demo
```

Bare `//nolint` is rejected by the tooling, and a justified-but-wrong one is
rejected in review. Config-level scoping (exclusions.rules, per-path rules
with `warn-unused: true`) is always preferred over inline suppression because
it is visible in one place and fails loudly when it stops matching anything.

## Mechanism analysis

Why each gate changes agent behavior, not just detects after the fact:

- **The lint roster removes negotiation.** print-debugging, direct wall-clock
  reads, unwrapped errors, magic switch defaults, and interface-returning
  constructors each produce a named finding the agent must refactor away;
  "it compiles" stops being the bar.
- **Executable architecture plus internal/** converts layering from tribal
  memory into two deterministic failures: depguard names the illegal edge
  inside the module, and the compiler rejects the whole module from outside
  it. Agents stop guessing boundaries because crossing one fails within
  seconds.
- **Race detector + shuffle on EVERY test run** attacks hidden coupling and
  shared-state shortcuts continuously, not just in a special nightly job.
- **Coverage floors with cross-package attribution** kill vacuous tests: a
  test that executes code without constraining it cannot hold 92% once real
  logic lands, and `-coverpkg` prevents the integration test's adapter work
  from disappearing between package boundaries.
- **govulncheck beats pattern scanners because of call-graph reachability:**
  it loads your program, builds the import/call graph, and fails only for
  vulnerabilities with a reachable path from your code to the vulnerable
  symbol. A vulnerable-but-unreachable dependency stays noisy-in-report,
  silent-in-gate, so the gate cannot be trained to cry wolf. govulncheck's
  own docs describe the model (<https://go.dev/blog/vuln>); gosec complements
  it with source-level SAST for credentials, weak crypto, and unsafe temps.
- **Deadcode via call-graph reachability** (x/tools deadcode,
  <https://pkg.go.dev/golang.org/x/tools/cmd/deadcode>) closes the accretion
  channel: unused helpers die in review the day they appear, not years later.
- **Negative fixtures discipline the gates themselves.** When a golangci
  release drops or renames a linter (as v2 did repeatedly — exhaustruct
  became exhaustruct_v5 in the very pin this template uses),
  `bad_examples/assert.sh` fails the same day the enforcement disappears.
  Strictness you cannot observe degrading is not strictness; it is a mood.
