# Kotlin language specification

This template is the **experimental** implementation of
[`docs/CONTRACTS.md`](../docs/CONTRACTS.md) v2 for Kotlin/JVM. Silence here
means compliance with the contract; deviations and `SKIP_UNSUPPORTED` gates
are called out explicitly.

## Philosophy

CI is the style guide ([`docs/PHILOSOPHY.md`](../docs/PHILOSOPHY.md)). For a
coding agent working in Kotlin this pack's definition of "done" is
`./verify.sh` printing PASS (or an honest SKIP) for every requested
capability. Experimental status means unimplemented gates must say
`SKIP_UNSUPPORTED(reason)` rather than fake a pass.

## Toolchain

| Concern | Tool | Pin | Why | Source |
| --- | --- | --- | --- | --- |
| Runtime | JDK 21 (LTS) | `jvmToolchain(21)` | current LTS line used by the official Gradle image | <https://adoptium.net/> |
| Image | `gradle:8.14-jdk21` | Dockerfile `FROM` | official image; Gradle 8.14.x + Temurin 21 + git | <https://hub.docker.com/_/gradle> |
| Language | Kotlin JVM | `2.1.20` | Kotlin 2.x line compatible with Gradle 8.14 | <https://kotlinlang.org/docs/releases.html> |
| Build | Gradle Kotlin DSL | 8.14 via image (wrapper generated when present) | typed DSL; `allWarningsAsErrors` | <https://kotlinlang.org/docs/gradle-configure-project.html> |
| Format + lint | ktlint via `org.jlleitschuh.gradle.ktlint` | plugin `12.3.0`, ktlint `1.5.0` | official Kotlin style; check-only | <https://github.com/JLLeitschuh/ktlint-gradle> |
| Tests | JUnit Jupiter | BOM `5.11.4` | requested runner; zero-test filter fails | <https://junit.org/junit5/> |
| Package | `application` + `installDist` | Gradle | smoke-runs `Money(0, "ZZZ")` | Gradle Application plugin |

Quality tools are not baked into the image. Bootstrap resolves the compiler,
JUnit, and ktlint from `build.gradle.kts` into workspace-relative
`GRADLE_USER_HOME=.gradle-home`.

## Gate-by-gate walkthrough

`./verify.sh` prints one `GATE <capability>: ...` line per requested
capability, in canonical order.

1. **bootstrap** — `gradle compileTestKotlin`. Resolves the Kotlin compiler,
   stdlib, JUnit, and ktlint at the pinned versions.
2. **format** — `ktlintCheck`. Never rewrites. Fixture:
   `bad_examples/unformatted/Unformatted.kt` → `standard:indent`.
3. **lint** — `ktlintCheck` again. ktlint owns both layout and style in this
   experimental pack (no overlapping detekt yet). Fixture:
   `bad_examples/lint/WildcardImport.kt` → `no-wildcard-imports`.
4. **compile** — `compileKotlin compileTestKotlin` with
   `allWarningsAsErrors` and toolchain 21. Production and tests type-check.
5. **architecture** — `SKIP_UNSUPPORTED(ArchUnit not yet wired in experimental pack)`.
6. **unit** — Gradle `unitTest` (JUnit under `com.warehouse.domain.*`).
   `failOnNoMatchingTests` makes an empty suite an error.
7. **property** — `SKIP_UNSUPPORTED(kotest property not yet wired; jqwik denylisted)`.
   jqwik ships an Anti-AI Usage Clause; this repository is agent-maintained.
8. **integration** — Gradle `integrationTest` (JUnit under
   `com.warehouse.application.*`) driving the place-order pipeline through
   in-memory adapters, including compensation and idempotency.
9. **package** — `installDist` then run the launcher; stdout must contain
   `warehouse-ok ZZZ`.
10. **coverage** — `SKIP_UNSUPPORTED(Kover not yet wired in experimental pack)`.
11. **dead-code** — `SKIP_UNSUPPORTED(no Kotlin unreachable-code gate wired)`.
12. **sast** — `SKIP_UNSUPPORTED(detekt security not yet wired in experimental pack)`.
13. **dependency-vulnerability** — `SKIP_UNSUPPORTED(no pinned JVM advisory scanner in this pack yet)`.
14. **dependency-policy** — `SKIP_UNSUPPORTED(Gradle dependency analysis not yet wired)`.
15. **lock-integrity** — `SKIP_UNSUPPORTED(Gradle dependency locking not yet wired)`.
16. **negative-fixtures** — `bash bad_examples/assert.sh`.
17. **mutation** — `SKIP_UNSUPPORTED(PIT Kotlin bytecode mapping not yet fixture-proven)`.
    Honest skip, never a fake pass (ADR-005 / AGENT_HANDOFF §19.3).
18. **conformance** — `SKIP_UNSUPPORTED(adapter not yet wired to shared JSON vectors)`.
19. **reproducibility** — `SKIP_UNSUPPORTED(two-clean-build comparison is WP7 root evidence)`.

## Domain notes

Same warehouse-order v2 as Python:

- `Money` stores `Long` minor units; currency is ISO-style `^[A-Z]{3}$`; `ZZZ`
  is valid; overflow is `InvalidOrderException`.
- `Quantity` is a strictly positive `Int` (`1..Int.MAX_VALUE`).
- `Sku` strips only ASCII space/tab/CR/LF; UTF-8 length `1..=64`.
- `Order` takes an injected `OrderId`; `NEW → PAID → SHIPPED`; `pay` on `PAID`
  is invalid; shipped mutations are `OrderAlreadyShippedException`.
- `PlaceOrderUseCase` validates, `reserveAll`, charges, marks `PAID`, saves;
  charge/save failures compensate (release / refund+release) and surface
  `CompensationFailureError` when compensation itself fails.

## Deliberate non-enforcements

- **ktlint owns both format and lint.** detekt is the Kotlin-native quality
  analyzer listed in the onboarding blueprint; it is not wired yet. Running
  `ktlintCheck` twice is redundant but not a no-op: the tool still checks
  sources, and distinct fixtures prove indent vs wildcard-import.
- **No Gradle wrapper checksum in the image-only fallback.** When `gradlew`
  is present it is preferred; otherwise the official `gradle:8.14-jdk21`
  image provides the `gradle` binary. Wrapper generation is the intended
  supply-chain pin.
- **No ArchUnit, Kover, detekt-security, OWASP, or PIT** in this experimental
  cut. Each is a named SKIP, not a silent pass.
- **Property tests omitted** until a trust-reviewed Kotlin generator exists.
  jqwik is denylisted (Anti-AI Usage Clause), matching the Java pack.

## Workflows

```bash
docker compose build kotlin     # not in the default Compose file (inDefault false)
# or: docker build -t warehouse-kotlin kotlin && docker run --rm -v "$PWD/kotlin":/workspace warehouse-kotlin ./verify.sh
```

The language is `experimental` and `inDefault: false`, so
`scripts/verify-all.sh` does not include it until a later promotion.
