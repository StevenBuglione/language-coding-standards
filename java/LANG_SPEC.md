# Java language specification

This template is the reference implementation of [`docs/CONTRACTS.md`](../docs/CONTRACTS.md)
for Java. Every knob lives in [`pom.xml`](pom.xml) and the three analyzer
configs ([`checkstyle/checkstyle.xml`](checkstyle/checkstyle.xml),
[`pmd/pmd.xml`](pmd/pmd.xml),
[`spotbugs/exclude.xml`](spotbugs/exclude.xml)); this document explains why
each knob sits where it does, what it forbids, and where we deliberately chose
not to enforce. Silence here means compliance with the contract; deviations
are called out explicitly.

## 1. Philosophy

CI is the style guide ([`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md)). For a
coding agent working in Java this has one concrete consequence: the agent's
entire definition of "done" is `./verify.sh` printing eleven PASS lines. So
every property worth having is expressed mechanically:

- strictness becomes `-Werror -Xlint:all` plus four analyzer layers whose
  every finding fails its phase;
- architecture becomes an ArchUnit layered contract that fails the build, not
  an ADR nobody reads;
- honest tests become JaCoCo line+branch floors plus (nightly) mutants;
- trust in the gates themselves becomes `bad_examples/`, fixtures each gate
  must reject on demand.

Java-specific reality shapes some choices: the compiler already enforces a lot
(types, sealed exhaustiveness), so the template's job is to push the compiler
to maximal settings and layer analyzers only where the compiler is silent.

## 2. Toolchain

| Concern | Tool | Pin | Why | Source |
| --- | --- | --- | --- | --- |
| Runtime | JDK 25 (LTS) | `maven.compiler.release=25`; enforcer `requireJavaVersion [25,)` | current LTS line; the release pin makes cross-JDK drift a build failure | <https://adoptium.net/> |
| Image | `maven:3.9-eclipse-temurin-25` | Dockerfile `FROM` | official image; Maven + Temurin JDK 25 + git for the container preamble | <https://hub.docker.com/_/maven> |
| Build | Maven via committed wrapper | wrapper 3.3.4, distribution `apache-maven-3.9.16-bin.zip`, `distributionSha256Sum` + `wrapperSha256Sum` pinned | byte-for-byte reproducible builds; checksum pins make supply-chain substitution a hard failure | <https://maven.apache.org/wrapper/#use-ad-hoc>, <https://maven.apache.org/security.html> |
| Format | spotless-maven-plugin + google-java-format | 3.10.0 / 1.36.1 | formatter is non-configurable-by-design (GOOGLE style, 100 cols); `spotless:check` never rewrites | <https://github.com/diffplug/spotless/tree/main/plugin-maven>, <https://github.com/google/google-java-format> |
| Compile-time defects | Error Prone as `-Xplugin` under javac | 2.50.0 (`error_prone_core`) | static analysis inside the compiler at full-fidelity type info; runs on main AND test compile | <https://errorprone.info/bugpatterns>, <https://github.com/google/errorprone> |
| Nullness | NullAway as EP plugin | 0.14.0; `JSpecifyMode=true`, `OnlyNullMarked=true` | JSpecify `@NullMarked` packages become compile-error nullness contracts | <https://github.com/uber/NullAway/wiki/JSpecify-Support>, <https://jspecify.dev/> |
| Lint (structure) | Checkstyle via maven-checkstyle-plugin | checkstyle 14.0.0 / plugin 3.6.0 | naming, size caps, imports, doc presence — the structural half of lint | <https://checkstyle.org/checks.html> |
| Lint (semantics) | PMD via maven-pmd-plugin | PMD 7.26.0 / plugin 3.28.0; errorprone+multithreading+design+bestpractices categories | semantic defect classes Checkstyle cannot see | <https://docs.pmd-code.org/latest/pmd_rules_java.html> |
| SAST | SpotBugs + findsecbugs via spotbugs-maven-plugin | 4.10.4.0 / 1.14.0; effort Max, threshold Low | bytecode-level bug patterns plus security taint rules = the security gate | <https://spotbugs.github.io/>, <https://find-sec-bugs.github.io/> |
| Architecture | ArchUnit | 1.5.0 | executable layered contract + cycle freedom, run as part of the test suite | <https://archunit.org/use-guide> |
| Tests | JUnit Jupiter BOM + AssertJ + Mockito | junit-bom 5.14.4 / AssertJ 3.27.7 / Mockito 5.23.0 (STRICT_STUBS) | fakes are preferred; mocks exist only for orchestration-order proofs, STRICT_STUBS makes every stub load-bearing | <https://junit.org/junit5/>, <https://assertj.github.io/doc/>, <https://site.mockito.org/> |
| Coverage | JaCoCo | 0.8.15; LINE/BRANCH COVEREDRATIO bound to `verify` | branch-aware coverage floor enforced by the lifecycle itself | <https://www.jacoco.org/jacoco/trunk/doc/check-mojo.html> |
| Mutation (config only) | pitest | 1.25.9 (+ junit5 plugin 1.2.3); `mutationThreshold` 70 | configured now, scheduled never in PR CI — nightly tier only | <https://pitest.org/quickstart/maven/> |

Deviation from the brief's "JUnit5 BOM" wording: pinned **within** the 5.x
line (5.14.4, its latest). JUnit 6 exists but is a platform-generation jump
(Java 17 baseline, new BOM coordinates) with no benefit this template needs;
the Jupiter programming model is identical.

### Why Maven over Gradle

The build system is part of the threat model. A coding agent that wants to
silence a gate has two routes: edit the code until it passes (intended), or
edit the build until the gate stops running (tampering). Gradle builds are
programs — Kotlin/Groovy scripts with conditionals, closures, arbitrary I/O —
so a tampering route can be made to look like ordinary refactoring:
`if (!ci) skip tasks`, dynamic task graph surgery, environment sniffing.
Maven POMs are declarative XML: there is no execution model to hide logic in.
A diff that weakens a gate is a diff that deletes a `<execution>` or a rule —
visible in review, unrepresentable as innocent code motion. That is also why
every plugin is pinned through `<pluginManagement>` with every version in a
property: version drift shows up as one-line diffs.

### Why four analyzer layers

Error Prone, Checkstyle, PMD and SpotBugs cover disjoint defect classes, and
no subset subsumes another:

- **Error Prone** sees through javac's own type attribution — pattern-matches
  over real ASTs with resolved types (boxed equality, unused variables,
  format-string mismatches).
- **Checkstyle** works at the source level without semantic analysis —
  naming, file/method size caps, import hygiene, doc presence. Cheap,
  deterministic, zero false positives on our curated config.
- **PMD** sits between them: source-level rules with light type use — design
  smells (parameter bloat, class length) and category sweeps
  (multithreading, best practices).
- **SpotBugs** analyzes compiled bytecode — escape-analysis findings source
  tools miss (mutable reference exposure) — and findsecbugs adds the
  security-taint vocabulary that turns the security phase into a real SAST.

Running any single tool would leave whole defect classes invisible; the
negative fixtures pin each tool's ability to bite.

## 3. Gate-by-gate walkthrough

`./verify.sh` runs these phases in canonical order, printing one
`GATE <phase>: PASS` line each. Every `mvnw` invocation is batch mode,
`--no-transfer-progress`, with `-Dmaven.repo.local=$PWD/.m2repo` so all
caches stay workspace-relative (CONTRACTS §4). Each phase below names the
fixture in [`bad_examples/`](bad_examples/) that proves it bites.

1. **deps** — `dependency:go-offline`. Warms `.m2repo` with the full
   plugin+dependency graph at pinned versions. Nothing to bite here by
   design: version-range bans live in `deps-hygiene`.
2. **format** — `spotless:check` (google-java-format, GOOGLE style). Never
   rewrites. Fixture: `format/Misformatted.java` — hand-mangled indentation
   and spacing that GJF would normalize; the negative phase's scoped
   `spotless:check` reports it as `format violations` and exits nonzero.
3. **lint** — `checkstyle:check pmd:pmd pmd:check`. Fixtures:
   `StyleViolation.java` → checkstyle `AvoidStarImport` +
   `RegexpSingleline` (System.out ban); `complexity/PmdViolation.java` → PMD
   `ExcessiveParameterList`. The negative phase asserts stable rule IDs from
   console output.
4. **types** — `test-compile`: javac `-Werror -Xlint:all,-processing` with
   Error Prone + NullAway wired as `-Xplugin`s (their `--add-exports` live in
   [`.mvn/jvm.config`](.mvn/jvm.config)). Fixture: `types/TypesViolation.java`
   → `[NullAway]` non-null-return diagnostic and Error Prone
   `BoxedPrimitiveEquality`.
5. **arch** — `test -Dtest=ArchitectureTest`: ArchUnit layered contract
   (Adapters may not be accessed by any layer; Application only by Adapters;
   Domain only by Application/Adapters), domain purity against everything,
   and slice cycle-freedom. Fixture: `arch/LoyalDomainService.java` reaching
   an adapter, caught by the mirrored `ArchRulesTest` failing with
   `Architecture Violation`.
6. **test** — `test`: every domain invariant, integration paths over the
   in-memory adapters (happy, insufficient stock, declined payment, invalid
   lines), and Mockito STRICT_STUBS orchestration-order tests.
7. **coverage** — `verify`: full lifecycle under JaCoCo with LINE and BRANCH
   COVEREDRATIO checks bound at verify (floors below). Runs the unit+arch
   suite a second time — accepted cost of one canonical lifecycle command.
8. **deadcode** — `dependency:analyze-only` with warnings fatal. Unused-declared
   dependencies fail unless explicitly justified in `pom.xml`; used-undeclared
   ones always fail. Known gap: javac/-Xlint does not report unused private
   members; Error Prone's unused-symbol checks partially close it. Documented
   rather than hidden.
9. **security** — `spotbugs:check` at effort Max / threshold Low with
   findsecbugs: this IS the SAST gate. Fixture:
   `security/SecurityViolation.java` → `HARD_CODE_PASSWORD`.
10. **deps-hygiene** — `enforcer:enforce dependency:analyze-only`. Enforcer
    rules: `requireJavaVersion [25,)`, `requireMavenVersion`,
    `dependencyConvergence`, `requirePluginVersions`, `banDynamicVersions`,
    and an active-but-empty `bannedDependencies` hook.
11. **negative** — `bad_examples/assert.sh`: wipes `target/`, then re-invokes
    each analyzer scoped to its fixture via the `fixture.include` /
    `fixture.test.include` properties, asserting nonzero exit plus the stable
    signal from the manifest table atop the script.

The optional `mutation` phase prints `GATE mutation: SKIP (nightly tier only)`
unless `VERIFY_TIER=full`, in which case pitest runs with
`mutationThreshold` (default 70, override `MUTATION_FLOOR`). Configured but
unscheduled — see roadmap note below.

## 4. Thresholds

| Threshold | Value | Rationale | Trade-off |
| --- | --- | --- | --- |
| Checkstyle `MethodLength` / PMD `ExcessiveMethodLength` | 60 / flags ≥60 | long methods hide branching bugs; forces extraction early | occasional legitimate table-driven method needs splitting |
| Checkstyle `ParameterNumber` / PMD `ExcessiveParameterList` | 5 / flags ≥6 | parameter bundles mean a value object is missing | constructors of genuinely wide config objects need a builder |
| Checkstyle `FileLength` / PMD `ExcessiveClassLength` | 300 / flags ≥300 | files accrete; the cap forces decomposition | large enums/records need splitting by responsibility |
| Checkstyle `CyclomaticComplexity` | 10 | classic ceiling; matches PMD default | branchy parsers need state machines |
| Checkstyle `NestedBlockDepth` | 4 | deep nesting is unreadable and untestable | guard-clause style required |
| Checkstyle `LineLength` | 100 | google-java-format's own wrap column; formatter and linter agree | none — formatter produces it |
| Checkstyle `MagicNumber` ignores | −1, 0, 1, 2 + field declarations | structural numbers vs semantic constants | named constants required elsewhere |
| NullAway | `JSpecifyMode=true`, `OnlyNullMarked=true` | checks exactly the packages that opted in via `@NullMarked` package-infos (all of them here) | a forgotten package-info silently opts out — caught by review and by the arch scan's package expectations |
| SpotBugs effort/threshold | Max / Low | maximum recall for the SAST gate | needs the small reasoned exclude list below |
| JaCoCo measured baseline (first green run) | **LINE 99.17%** (119/120), **BRANCH 100.00%** (32/32) | R3 reference point | single missed line is a defensive `requireNonNullElse` fallback |
| JaCoCo floors (`jacoco.line.floor` / `jacoco.branch.floor`) | **0.95** / **0.96** (= measured − 4, min 80 / min 70) | R3 buffer absorbs small refactors without licensing gaps | new branches need tests within ~4 points of landing |
| pitest `mutationThreshold` | 70 | nightly-tier aspiration, tunable before scheduling | unscheduled; not yet load-bearing |

## 5. Deliberate non-enforcements and deviations

Every entry here is a decision, recorded so silence cannot be mistaken for
oversight.

- **Property-based testing is omitted, on purpose, because jqwik forbids the
  alternative.** The contract asks for two property tests per template. The
  JVM property-testing library jqwik ships an explicit Anti-AI Usage Clause
  ([jqwik 1.10.1 release notes](https://github.com/jqwik-team/jqwik/releases/tag/1.10.1)):
  > Warning: Starting with version 1.10 jqwik comes with an Anti-AI Usage Clause!
  > Usage with any 'AI' agent is strongly discouraged.
  > Jqwik's log output may confuse the agent.
  >
  > This project is not meant to be used by any “AI” coding agents at all.
  >
  > Use of jqwik >= 1.10 with coding agents is strongly discouraged.
  >
  > Jqwik's output to stdout may confuse AI-based agents.

  This repository is authored and maintained by coding agents; adopting a
  dependency whose license-equivalent terms forbid that usage would violate
  the clause on every commit. The property tests' target invariants (Money
  addition commutativity, Order total invariant under random valid lines)
  are instead covered exhaustively by deterministic unit cases at the
  boundaries (zero, cache edges, mixed currency, duplicate SKUs). Revisit if
  jqwik ever lifts the clause or an unpinned fork appears.

- **Checkstyle does not import `google_checks.xml` verbatim.** The curated
  config seeds Google-style essentials (naming, modifiers, one-type-per-file)
  but omits layout modules wholesale: google-java-format owns layout in the
  format phase, and duplicating ownership makes the two gates fight. It also
  avoids coupling this repo to whatever suppression-file references ship
  inside the upstream config. The division of labor is documented above and
  in the config header.

- **No `MissingSwitchDefault`.** Pattern switches over sealed hierarchies are
  exhaustive-checked by javac itself; forcing `default` would disable that
  enforcement for future permitted components. PMD's equivalent rule is
  excluded for the same reason (reason comment lives in `pmd/pmd.xml`).

- **`DataflowAnomalyAnalysis` excluded** — DD/UDD anomalies misfire on
  accumulator reassignment; the same defect classes are covered by Error
  Prone + NullAway at higher fidelity (reason in `pmd/pmd.xml`).

- **`LawOfDemeter` / `UseObjectForClearerAPI` excluded** — both fire on the
  record-component access idiom the canonical domain is built from; boundary
  discipline is ArchUnit's decidable job (reasons in `pmd/pmd.xml`).

- **`EI_EXPOSE_REP` / `EI_EXPOSE_REP2` excluded for adapters** — the in-memory
  doubles intentionally alias mutable aggregates; identity preservation IS
  the port contract (reason in `spotbugs/exclude.xml`). Production code
  outside adapters must not rely on this exclusion — entries are global, so
  reviewers watch for leaks elsewhere.

- **`deadcode` and `deps-hygiene` ship no negative fixtures.** Their failure
  modes live in POM configuration (a stale dependency declaration, a version
  range), not in Java source; a fixture would have to tamper with the build
  file itself, which is the tampering these gates exist to catch. The gates
  are instead proven by their real configuration: `failOnWarning=true` plus
  the two justified ignore entries, and the enforcer rule list, both visible
  in `pom.xml`.

- **Tests are outside Checkstyle/PMD/SpotBugs scans.** Test code is still
  formatted (spotless includes `src/test/java`), compiled under full Error
  Prone + NullAway strictness, and executed under coverage. Structural lint
  on tests buys noise, not safety; documented rather than hidden.

- **Unused-private-member gap in `deadcode`.** javac's `-Xlint` has no
  unused-private diagnostics; Error Prone catches several unused-symbol
  patterns, `dependency:analyze-only` closes the dependency half. Accepted,
  documented gap.

- **Coverage re-runs the suite.** `mvn verify` executes validate→verify, so
  tests run twice across the test and coverage phases. One canonical
  lifecycle command was chosen over surefire fork tricks; the cost is
  seconds at this scale.

## 6. Workflows

### Clone and go

1. Copy `java/` wholesale into your repository.
2. Rename the package (see README step 2) and keep the gate configs pointed
   at your sources.
3. Keep `bad_examples/` paired with the `negative` phase; deleting one without
   the other removes the proof that your gates bite.
4. Add runtime dependencies consciously: convergence is enforced, versions
   must be pinned, and `dependency:analyze-only` will demand justification for
   anything declared-but-unused or used-but-undeclared.
5. Regenerate nothing by hand: bump pins one property at a time and let the
   gates arbitrate.

### Hermetic run

```bash
docker compose build java     # official maven:3.9-eclipse-temurin-25, nothing baked in
docker compose run --rm java  # mounts ./java at /workspace, runs verify.sh
docker compose run --rm java bash -c './verify.sh lint'   # iterate targeted phases
```

Caches (`.m2repo`, `.m2wrapper` via `MAVEN_USER_HOME`) point at
workspace-relative gitignored directories, satisfying CONTRACTS §4 — nothing
leaks outside the workspace or into image layers. Quality tools are never
baked into the image; the `deps` phase pulls them at pinned versions from the
committed POM on every run. The wrapper distribution itself is
checksum-pinned (`distributionSha256Sum`, `wrapperSha256Sum`), so even the
build tool arrives verified.

### Suppression policy

Inline suppressions exist for the rare case where a rule misfires on correct
code. They are loud by convention and enforced by review:

```java
@SuppressWarnings("UnusedVariable") // event loop keeps the handle for reconnects; removal breaks recovery
```

- `@SuppressWarnings` must name the specific check AND carry a trailing
  justification sentence. Bare suppression is treated as gate tampering.
- Filter-file entries (`pmd/pmd.xml` excludes, `spotbugs/exclude.xml`
  `<Match>`) REQUIRE a reason comment per entry; the configs reject nothing
  automatically — review does — which is why every existing entry carries one.
- Config-level scoping (`fixture.include` properties in `bad_examples/`) is
  always preferred over inline suppression because it is visible in one place.

## 7. Mechanism analysis

Why each gate changes agent behavior, not just detects after the fact:

- **`-Werror` + Error Prone + NullAway** removes negotiation at the earliest
  possible moment: the agent cannot ship boxed equality, a nullable leak, or
  a swallowed exception because compilation itself refuses. Fixing forward is
  cheaper than arguing with the compiler, and the agent learns to annotate
  and null-check first because annotation-last always loses.
- **Four disjoint analyzers** close the "it passed X" rationalization: style,
  semantics, bytecode and security each own defect classes the others cannot
  see, so no single-tool blind spot becomes an excuse.
- **Executable architecture** converts "don't import adapters from the
  domain" into a failing test within seconds; agents stop guessing boundaries
  because crossing one is deterministically red.
- **JaCoCo line+branch floors** attack vacuous testing: executing code without
  constraining it cannot hold the floor once real logic lands, and branch
  counting kills the assert-free happy-path test.
- **STRICT_STUBS** disciplines mocking itself: a stub that no interaction uses
  fails the test, so doubles stay minimal and honest — which is also why
  fakes are preferred and mocks confined to orchestration-order proofs.
- **Enforcer + analyze-only** close the quiet rot channels: conflicting
  transitive versions, floating ranges, undeclared usage, dead declarations.
  Each failure message points at the exact artifact to fix.
- **Negative fixtures** discipline the gates themselves. When a Checkstyle
  release drops a rule or findsecbugs renames a pattern, the matching fixture
  stops being rejected and the `negative` phase fails the same day — the
  toolchain carries its own regression tests, so strictness cannot silently
  decay into mood.

## Roadmap notes

- **Mutation testing** (pitest) is configured with a documented
  `mutationThreshold` but unscheduled in PR CI; wire it into the nightly
  `full.yml` tier when wall-clock budget allows.
- **API freeze** tooling (japicmp or similar) is intentionally absent at v0;
  revisit once the template's API stabilizes.
