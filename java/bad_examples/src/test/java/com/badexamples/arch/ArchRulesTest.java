package com.badexamples.arch;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

/**
 * The SAME rule shape as the template's ArchitectureTest, pointed at the
 * fixture tree: it must FAIL because LoyalDomainService imports the adapter.
 */
@AnalyzeClasses(packages = "com.badexamples", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchRulesTest {

  /** Must be violated by the fixture — its failure IS the expected signal. */
  @ArchTest
  static final ArchRule domainMustNotReachAdapters = noClasses()
      .that()
      .resideInAPackage("..arch.domain..")
      .should()
      .dependOnClassesThat()
      .resideInAPackage("..arch.adapter..");
}
