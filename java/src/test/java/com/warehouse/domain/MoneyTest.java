package com.warehouse.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Currency;
import java.util.Locale;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Money invariant tests: non-negativity, currency safety, scaling. */
class MoneyTest {

  private static final Currency USD = Currency.getInstance(Locale.US);
  private static final Currency EUR = Currency.getInstance("EUR");

  @ParameterizedTest
  @ValueSource(ints = {-1, -500})
  void rejectsNegativeAmounts(int negative) {
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
  void recordsWithSameFieldsAreEqual() {
    assertThat(new Money(500, USD)).isEqualTo(new Money(500, USD));
    assertThat(new Money(500, USD)).isNotEqualTo(new Money(501, USD));
    assertThat(new Money(500, USD)).isNotEqualTo(new Money(500, EUR));
  }
}
