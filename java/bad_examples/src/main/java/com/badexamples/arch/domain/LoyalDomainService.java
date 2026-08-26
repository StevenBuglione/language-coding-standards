package com.badexamples.arch.domain;

import com.badexamples.arch.adapter.ThirdPartyAdapter;

/** Deliberate architecture violation: domain code reaching out to an adapter. */
public final class LoyalDomainService {

  /** Deliberate violation; never call this. */
  public void act() {
    ThirdPartyAdapter.call();
  }
}
