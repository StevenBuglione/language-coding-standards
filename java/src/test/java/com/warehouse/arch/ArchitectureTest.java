package com.warehouse.arch;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.library.Architectures.layeredArchitecture;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.library.dependencies.SlicesRuleDefinition;

/**
 * Executable architecture (CONTRACTS.md §1 arch phase): the layered contract adapters -&gt;
 * application -&gt; domain and cycle freedom across slices.
 *
 * <p>Analysis covers production classes only: tests legitimately reach every layer to wire
 * fixtures, which would otherwise masquerade as violations.
 */
@AnalyzeClasses(packages = "com.warehouse", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

  /** Layered contract: adapters may not be reached by any layer inward. */
  @ArchTest
  static final ArchRule layersPointOutwardOnly =
      layeredArchitecture()
          .consideringAllDependencies()
          .layer("Domain")
          .definedBy("com.warehouse.domain..")
          .layer("Application")
          .definedBy("com.warehouse.application..")
          .layer("Adapters")
          .definedBy("com.warehouse.adapters..")
          .whereLayer("Adapters")
          .mayNotBeAccessedByAnyLayer()
          .whereLayer("Application")
          .mayOnlyBeAccessedByLayers("Adapters")
          .whereLayer("Domain")
          .mayOnlyBeAccessedByLayers("Application", "Adapters");

  /** The domain stays pure even against packages outside the three layers. */
  @ArchTest
  static final ArchRule domainNeverReachesOutward =
      noClasses()
          .that()
          .resideInAPackage("com.warehouse.domain..")
          .should()
          .dependOnClassesThat()
          .resideInAnyPackage("com.warehouse.application..", "com.warehouse.adapters..");

  /**
   * Currency codes are ISO-style strings; {@code java.util.Currency} rejects valid codes such as
   * {@code ZZZ} and must not be the domain's public (or internal) type.
   */
  @ArchTest
  static final ArchRule domainDoesNotUseJdkCurrency =
      noClasses()
          .that()
          .resideInAPackage("com.warehouse.domain..")
          .should()
          .dependOnClassesThat()
          .haveFullyQualifiedName("java.util.Currency");

  /** Order identifiers are injected strings; the domain must not mint {@code UUID}s. */
  @ArchTest
  static final ArchRule domainDoesNotUseUuid =
      noClasses()
          .that()
          .resideInAPackage("com.warehouse.domain..")
          .should()
          .dependOnClassesThat()
          .haveFullyQualifiedName("java.util.UUID");

  /** No package cycles between top-level warehouse slices. */
  @ArchTest
  static final ArchRule slicesAreCycleFree =
      SlicesRuleDefinition.slices().matching("com.warehouse.(*)..").should().beFreeOfCycles();
}
