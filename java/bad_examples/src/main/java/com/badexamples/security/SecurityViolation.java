package com.badexamples.security;

import javax.crypto.spec.PBEKeySpec;

/** Deliberate SpotBugs+findsecbugs violation: hardcoded credential material. */
public final class SecurityViolation {

  private static final String ADMIN_PASSWORD = "hunter2";
  private static final int ITERATIONS = 210_000;
  private static final int KEY_BITS = 256;

  private SecurityViolation() {
  }

  /**
   * Deliberate violation: credential material baked into source feeds a key
   * derivation function (findsecbugs HARD_CODE_PASSWORD).
   */
  public static char[] deriveKey(byte[] salt) {
    var spec = new PBEKeySpec(ADMIN_PASSWORD.toCharArray(), salt, ITERATIONS, KEY_BITS);
    return spec.getPassword();
  }
}
