package com.badexamples.style;

import java.util.List.*;

/** Deliberate checkstyle violations: star imports, printing, magic number, TODO sediment. */
public class StyleViolation {

  /** Deliberate violations; never call this. */
  public static void announce() {
    System.out.println("retry budget " + 3);
    // TODO: wire this to a real logger
    List.class.getName();
  }
}
