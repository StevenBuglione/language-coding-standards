# Kotlin template (experimental)

Experimental implementation of the harness contract in
[`docs/CONTRACTS.md`](../docs/CONTRACTS.md) v2: capability-gated `verify.sh`
wrapped around the canonical warehouse-order domain, plus `bad_examples/`
fixtures that prove format and lint still bite.

The stack: Kotlin JVM 2.1.20, JDK 21 toolchain, Gradle Kotlin DSL on
`gradle:8.14-jdk21`, ktlint 1.5.0, JUnit Jupiter 5.11. This pack is
**not** in the default `verify-all` set (`inDefault: false`).

## Use this template

1. Copy the `kotlin/` directory into your project.
2. Rename the package: move `src/main/kotlin/com/warehouse` and update
   `mainClass` in `build.gradle.kts`.
3. Keep `bad_examples/` paired with the `negative-fixtures` phase.
4. Swap the canonical domain for yours; keep the gates.

## Hermetic run

```bash
docker build -t warehouse-kotlin kotlin
docker run --rm -v "$PWD/kotlin":/workspace -w /workspace warehouse-kotlin bash ./verify.sh
docker run --rm -v "$PWD/kotlin":/workspace -w /workspace warehouse-kotlin bash ./verify.sh unit
```

Tool-by-tool rationale and SKIP reasons live in [`LANG_SPEC.md`](LANG_SPEC.md).
