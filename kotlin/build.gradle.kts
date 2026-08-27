import org.gradle.process.CommandLineArgumentProvider
import java.io.File

plugins {
    kotlin("jvm") version "2.2.10"
    `maven-publish`
    application
    id("org.jlleitschuh.gradle.ktlint") version "12.3.0"
    id("io.gitlab.arturbosch.detekt") version "1.23.8"
    id("org.jetbrains.kotlinx.kover") version "0.9.9"
}

kotlin {
    jvmToolchain(21)
    compilerOptions {
        allWarningsAsErrors.set(true)
    }
}

application {
    mainClass.set("com.warehouse.MainKt")
}

val ktlintCli: Configuration by configurations.creating

dependencies {
    testImplementation(platform("org.junit:junit-bom:5.11.4"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testImplementation("org.junit.jupiter:junit-jupiter-params")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("com.tngtech.archunit:archunit-junit5:1.3.2")
    testImplementation("io.kotest:kotest-property-jvm:5.9.1")
    testImplementation("io.kotest:kotest-assertions-core-jvm:5.9.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
    testImplementation("org.json:json:20250107")
    ktlintCli("com.pinterest.ktlint:ktlint-cli:1.5.0")
}

detekt {
    toolVersion = "1.23.8"
    buildUponDefaultConfig = true
    parallel = true
    source.setFrom("src/main/kotlin")
}

kover {
    reports {
        filters {
            excludes {
                classes("com.warehouse.MainKt")
            }
        }
        verify {
            rule {
                bound {
                    minValue.set(70)
                }
            }
        }
    }
}

publishing {
    publications {
        create<MavenPublication>("lib") {
            groupId = "com.warehouse"
            artifactId = "warehouse"
            version = "1.0.0"
            from(components["java"])
        }
    }
    repositories {
        maven {
            name = "localBuild"
            url = uri(layout.buildDirectory.dir("repo"))
        }
    }
}

ktlint {
    version.set("1.5.0")
    android.set(false)
    outputToConsole.set(true)
    ignoreFailures.set(false)
    enableExperimentalRules.set(false)
    filter {
        exclude { it.file.path.contains("${File.separator}bad_examples${File.separator}") }
    }
}

fun Test.configureJunit() {
    useJUnitPlatform()
    testLogging {
        events("passed", "skipped", "failed")
        showStandardStreams = false
    }
    filter {
        isFailOnNoMatchingTests = true
    }
}

tasks.test {
    configureJunit()
}

tasks.register<Test>("unitTest") {
    group = "verification"
    description = "Domain unit tests (com.warehouse.domain)"
    val testTask = tasks.test.get()
    testClassesDirs = testTask.testClassesDirs
    classpath = testTask.classpath
    configureJunit()
    filter {
        includeTestsMatching("com.warehouse.domain.*")
        isFailOnNoMatchingTests = true
    }
}

tasks.register<Test>("propertyTest") {
    group = "verification"
    description = "Kotest property tests (com.warehouse.property)"
    val testTask = tasks.test.get()
    testClassesDirs = testTask.testClassesDirs
    classpath = testTask.classpath
    configureJunit()
    filter {
        includeTestsMatching("com.warehouse.property.*")
        isFailOnNoMatchingTests = true
    }
}

tasks.register<Test>("architectureTest") {
    group = "verification"
    description = "ArchUnit layer tests"
    val testTask = tasks.test.get()
    testClassesDirs = testTask.testClassesDirs
    classpath = testTask.classpath
    configureJunit()
    filter {
        includeTestsMatching("com.warehouse.arch.*")
        isFailOnNoMatchingTests = true
    }
}

tasks.register<Test>("conformanceTest") {
    group = "verification"
    description = "Shared conformance/v2 JSON vectors"
    val testTask = tasks.test.get()
    testClassesDirs = testTask.testClassesDirs
    classpath = testTask.classpath
    configureJunit()
    filter {
        includeTestsMatching("com.warehouse.conformance.*")
        isFailOnNoMatchingTests = true
    }
}

tasks.register<Test>("integrationTest") {
    group = "verification"
    description = "Place-order integration tests (com.warehouse.application)"
    val testTask = tasks.test.get()
    testClassesDirs = testTask.testClassesDirs
    classpath = testTask.classpath
    configureJunit()
    filter {
        includeTestsMatching("com.warehouse.application.*")
        isFailOnNoMatchingTests = true
    }
}

tasks.register<JavaExec>("ktlintFixture") {
    group = "verification"
    description = "Run ktlint on -Pfixture=path for negative fixtures only"
    classpath = ktlintCli
    mainClass.set("com.pinterest.ktlint.Main")
    val fixture = providers.gradleProperty("fixture")
    argumentProviders.add(
        CommandLineArgumentProvider {
            listOf(fixture.get())
        }
    )
}

tasks.named<Jar>("jar") {
    archiveBaseName.set("warehouse")
    archiveVersion.set("1.0.0")
    manifest {
        attributes["Main-Class"] = "com.warehouse.MainKt"
    }
}
