package com.warehouse.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

/**
 * Deterministic generative money tests. jqwik is denylisted; this harness
 * replays a committed seed schedule rather than claiming shrinking.
 */
final class GenerativeMoneyTest {

  @Test
  void additionIsCommutativeAcrossSeededAmounts() {
    long[] amounts = {0L, 1L, 17L, 250L, 9_007_199_254_740_990L};
    for (long left : amounts) {
      for (long right : amounts) {
        if (left > Money.MAX_MINOR_UNITS - right) {
          continue;
        }
        Money a = new Money(left, "USD");
        Money b = new Money(right, "USD");
        assertEquals(a.add(b), b.add(a));
      }
    }
  }

  @Test
  void overflowIsRejected() {
    Money max = new Money(Money.MAX_MINOR_UNITS, "USD");
    assertThrows(InvalidOrderException.class, () -> max.add(new Money(1L, "USD")));
  }
}
