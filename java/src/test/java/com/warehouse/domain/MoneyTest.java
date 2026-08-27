package com.warehouse.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Money invariant tests: non-negativity, ISO-style currency, overflow, scaling. */
class MoneyTest {

  private static final String USD = "USD";
  private static final String EUR = "EUR";

  @ParameterizedTest
  @ValueSource(longs = {-1, -500})
  void rejectsNegativeAmounts(long negative) {
    assertThatThrownBy(() -> new Money(negative, USD))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("non-negative");
  }

  @Test
  void acceptsZeroAndPositiveAmounts() {
    assertThat(new Money(0, USD).minorUnits()).isZero();
    assertThat(new Money(1000, USD).minorUnits()).isEqualTo(1000);
  }

  @Test
  void acceptsSharedMaximumAndIsoStyleZzz() {
    assertThat(new Money(Money.MAX_MINOR_UNITS, USD).minorUnits()).isEqualTo(Money.MAX_MINOR_UNITS);
    assertThat(new Money(0, "ZZZ").currency()).isEqualTo("ZZZ");
  }

  @Test
  void rejectsAmountAboveSharedMaximum() {
    assertThatThrownBy(() -> new Money(Money.MAX_MINOR_UNITS + 1, USD))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("exceeds");
  }

  @ParameterizedTest
  @ValueSource(strings = {"usd", "US", "USDD", "", "US1"})
  void rejectsMalformedCurrency(String currency) {
    assertThatThrownBy(() -> new Money(1, currency))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("currency");
  }

  @Test
  void addsAmountsOfSameCurrency() {
    var sum = new Money(300, USD).add(new Money(700, USD));
    assertThat(sum).isEqualTo(new Money(1000, USD));
  }

  @Test
  void rejectsCrossCurrencyAdditionAsInvalidOrder() {
    var dollars = new Money(300, USD);
    var euros = new Money(300, EUR);
    assertThatThrownBy(() -> dollars.add(euros))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("currency mismatch");
  }

  @Test
  void addRejectsOverflowOfSharedMaximum() {
    var max = new Money(Money.MAX_MINOR_UNITS, USD);
    assertThatThrownBy(() -> max.add(new Money(1, USD)))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("overflows");
  }

  @Test
  void scalesByNonNegativeMultiplier() {
    var scaled = new Money(250, USD).times(4);
    assertThat(scaled).isEqualTo(new Money(1000, USD));
    assertThat(new Money(250, USD).times(0)).isEqualTo(new Money(0, USD));
  }

  @Test
  void rejectsNegativeMultiplier() {
    assertThatThrownBy(() -> new Money(250, USD).times(-2))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("non-negative");
  }

  @Test
  void timesRejectsOverflowOfSharedMaximum() {
    var max = new Money(Money.MAX_MINOR_UNITS, USD);
    assertThatThrownBy(() -> max.times(2))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("overflows");
  }

  @Test
  void timesRejectsLongOverflowAsInvalidOrder() {
    var max = new Money(Money.MAX_MINOR_UNITS, USD);
    assertThatThrownBy(() -> max.times(Integer.MAX_VALUE))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("overflows");
  }

  @Test
  void recordsWithSameFieldsAreEqual() {
    assertThat(new Money(500, USD)).isEqualTo(new Money(500, USD));
    assertThat(new Money(500, USD)).isNotEqualTo(new Money(501, USD));
    assertThat(new Money(500, USD)).isNotEqualTo(new Money(500, EUR));
  }
}
