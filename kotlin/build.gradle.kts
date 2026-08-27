import org.gradle.process.CommandLineArgumentProvider
import java.io.File

plugins {
    kotlin("jvm") version "2.1.20"
    application
    id("org.jlleitschuh.gradle.ktlint") version "12.3.0"
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
    ktlintCli("com.pinterest.ktlint:ktlint-cli:1.5.0")
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
