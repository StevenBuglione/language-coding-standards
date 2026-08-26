package com.badexamples.types;

/** Deliberate NullAway + Error Prone violations; compile must fail on this file. */
public final class TypesViolation {

  private TypesViolation() {
  }

  /**
   * Deliberate violation: returns null from a non-null return type inside a
   * {@code @NullMarked} package.
   *
   * @return nothing but failure — NullAway must reject this method
   */
  public static String greet(String name) {
    return null;
  }

  /**
   * Deliberate violation: reference comparison of boxed values.
   *
   * @return true only by accident of the Integer cache
   */
  public static boolean sameBoxed(Integer left, Integer right) {
    return left == right;
  }
}
