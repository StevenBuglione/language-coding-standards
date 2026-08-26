# Negative fixtures

Deliberately violating code that every gate must reject on demand
(CONTRACTS.md §3). `assert.sh` invokes each analyzer separately, scoped to
its fixture directory through the `fixture.include` / `fixture.test.include`
properties, asserts a nonzero exit plus the expected stable signal from the
manifest table at the top of the script, and wipes `target/` between runs.

| Fixture class | Directory | Trips gate | Signal |
| --- | --- | --- | --- |
| `Misformatted` | `format/` | format (`spotless:check`) | spotless `format violations` |
| `TypesViolation.greet` | `types/` | types (`mvnw compile`) | `[NullAway]` non-null return violation |
| `TypesViolation.sameBoxed` | `types/` | types (`mvnw compile`) | Error Prone `BoxedPrimitiveEquality` |
| `StyleViolation` | `style/` | lint (`checkstyle:check`) | `AvoidStarImport`, `RegexpSingleline` (printing) |
| `PmdViolation.configure` | `complexity/` | lint (`pmd:pmd pmd:check`) | `ExcessiveParameterList` |
| `SecurityViolation` | `security/` | security (`compile spotbugs:check`) | findsecbugs `HARD_CODE_PASSWORD` |
| `LoyalDomainService` | `arch/` | arch (`test`) | ArchUnit `Architecture Violation` |

The format fixture lives in its own directory because the OTHER fixtures are
deliberately not google-java-format clean and must stay that way — the
bad_examples spotless execution narrows its includes to `format/` only.

This POM is deliberately NOT part of any aggregator — `java/pom.xml` declares
no modules — so only `assert.sh` ever builds it. Deleting this directory
without deleting the `negative` phase removes the proof that your gates bite.
