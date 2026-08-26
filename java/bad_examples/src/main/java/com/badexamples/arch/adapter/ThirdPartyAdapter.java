package com.badexamples.arch.adapter;

/** Fixture standing in for an adapters-layer class. */
public final class ThirdPartyAdapter {

  private ThirdPartyAdapter() {
  }

  /** Deliberate target of an illegal inward dependency. */
  public static void call() {
    // No body needed to trip the architecture rule.
  }
}
