package com.warehouse.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** Sku invariant tests: ASCII-edge stripping, case, and UTF-8 byte length. */
class SkuTest {

  @ParameterizedTest
  @ValueSource(strings = {"", "   ", "\t\n", " \r "})
  void rejectsCodesEmptyAfterTrimming(String blank) {
    assertThatThrownBy(() -> new Sku(blank))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("non-empty");
  }

  @Test
  void stripsOnlyAsciiSpaceTabCrLf() {
    var sku = new Sku(" \t\r\nSKU-42 \t\r\n");
    assertThat(sku.code()).isEqualTo("SKU-42");
  }

  @Test
  void keepsInteriorSpacingIntact() {
    var sku = new Sku("SKU 42");
    assertThat(sku.code()).isEqualTo("SKU 42");
  }

  @Test
  void preservesCase() {
    assertThat(new Sku("sku-a").code()).isEqualTo("sku-a");
    assertThat(new Sku("sku-a")).isNotEqualTo(new Sku("SKU-A"));
  }

  @Test
  void preservesNbspPrefix() {
    assertThat(new Sku("\u00a0ABC").code()).isEqualTo("\u00a0ABC");
  }

  @Test
  void acceptsMaxUtf8Bytes() {
    assertThat(new Sku("A".repeat(Sku.MAX_UTF8_BYTES)).code()).hasSize(Sku.MAX_UTF8_BYTES);
  }

  @Test
  void rejectsAboveUtf8ByteLimit() {
    assertThatThrownBy(() -> new Sku("A".repeat(Sku.MAX_UTF8_BYTES + 1)))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("UTF-8 bytes");
  }
}
