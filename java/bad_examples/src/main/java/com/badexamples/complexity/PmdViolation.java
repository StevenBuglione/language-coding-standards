package com.badexamples.complexity;

/** Deliberate PMD violation: parameter bloat past the shared ladder cap of five. */
public final class PmdViolation {

  private PmdViolation() {
  }

  /**
   * Deliberate violation: eight loose parameters where a value object belongs
   * (ExcessiveParameterList, minimum=6).
   */
  public static void configure(
      int retries,
      int timeoutMillis,
      int maxConnections,
      int backoffMillis,
      int queueDepth,
      int batchSize,
      int cacheEntries,
      int workerCount) {
    // No body needed to trip the rule: the signature is the defect.
  }
}
