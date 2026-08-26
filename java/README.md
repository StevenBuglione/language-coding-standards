# Java template

Reference implementation of the harness contract in [`docs/CONTRACTS.md`](../docs/CONTRACTS.md):
eleven strict gates (`verify.sh`) wrapped around the canonical warehouse-order
domain, plus `bad_examples/` fixtures that prove every gate bites.

The stack: JDK 25 + Maven wrapper, Error Prone and NullAway at compile time,
Checkstyle + PMD as linters, SpotBugs + findsecbugs as SAST, ArchUnit as
executable architecture, JUnit 5 + AssertJ + Mockito under JaCoCo coverage
floors — every tool pinned by exact version in `pom.xml`.

## Use this template (clone → rename → go)

1. Copy the `java/` directory into your project.
2. Rename the package: move `src/main/java/com/warehouse` to your package,
   update `com.warehouse.*` references in `pom.xml` (pitest targets), the
   ArchUnit `@AnalyzeClasses` packages, and `bad_examples/` mirrors.
3. Delete `bad_examples/` only if you also delete the `negative` phase — a gate
   without its fixture is a gate you cannot trust. Keeping both is the point.
4. Swap the canonical domain for yours; keep the gates. Raise coverage floors
   when measurement shows headroom, never lower them to pass.
5. Run everything locally, hermetically: `docker compose run --rm java`
   from the repository root. Iterate until every GATE prints PASS.

Tool-by-tool rationale, thresholds, deliberate non-enforcements, and why
property-based testing is deliberately omitted live in
[`LANG_SPEC.md`](LANG_SPEC.md). The philosophy behind "CI is the style guide"
lives in [`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md).
