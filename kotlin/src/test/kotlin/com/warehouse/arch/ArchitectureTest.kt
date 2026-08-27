package com.warehouse.arch

import com.tngtech.archunit.core.importer.ClassFileImporter
import com.tngtech.archunit.core.importer.ImportOption
import com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses
import org.junit.jupiter.api.Test

class ArchitectureTest {
    private val classes =
        ClassFileImporter()
            .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
            .importPackages("com.warehouse")

    @Test
    fun domainDoesNotDependOnApplicationOrAdapters() {
        noClasses()
            .that()
            .resideInAPackage("com.warehouse.domain..")
            .should()
            .dependOnClassesThat()
            .resideInAnyPackage("com.warehouse.application..", "com.warehouse.adapters..")
            .check(classes)
    }

    @Test
    fun applicationDoesNotDependOnAdapters() {
        noClasses()
            .that()
            .resideInAPackage("com.warehouse.application..")
            .should()
            .dependOnClassesThat()
            .resideInAPackage("com.warehouse.adapters..")
            .check(classes)
    }
}
