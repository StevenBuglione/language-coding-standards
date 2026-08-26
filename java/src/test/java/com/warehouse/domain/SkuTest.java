package com.warehouse.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Sku invariant tests: trimming and non-emptiness. */
class SkuTest {

  @ParameterizedTest
  @ValueSource(strings = {"", "   ", "\t\n"})
  void rejectsCodesEmptyAfterTrimming(String blank) {
    assertThatThrownBy(() -> new Sku(blank))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("non-empty");
  }

  @Test
  void normalizesSurroundingWhitespaceOnCreation() {
    var sku = new Sku("  SKU-42  ");
    assertThat(sku.code()).isEqualTo("SKU-42");
  }

  @Test
  void keepsInteriorSpacingIntact() {
    var sku = new Sku("SKU 42");
    assertThat(sku.code()).isEqualTo("SKU 42");
  }
}
