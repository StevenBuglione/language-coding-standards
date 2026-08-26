package com.warehouse.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Quantity invariant tests: strict positivity. */
class QuantityTest {

  @ParameterizedTest
  @ValueSource(ints = {0, -1, -100})
  void rejectsZeroAndNegativeAmounts(int invalid) {
    assertThatThrownBy(() -> new Quantity(invalid))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("strictly positive");
  }

  @ParameterizedTest
  @ValueSource(ints = {1, 7, 1_000_000})
  void acceptsStrictlyPositiveAmounts(int valid) {
    assertThat(new Quantity(valid).value()).isEqualTo(valid);
  }
}
