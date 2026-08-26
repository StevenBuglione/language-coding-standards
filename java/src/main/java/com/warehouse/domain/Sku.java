package com.warehouse.domain;

/**
 * A stock-keeping-unit code, normalized to its trimmed form on creation.
 *
 * @param code non-empty trimmed stock-keeping-unit code
 */
public record Sku(String code) {

  /**
   * Trims surrounding whitespace and validates the non-empty invariant, so every {@code Sku}
   * observed downstream is normalized.
   *
   * @throws InvalidOrderException when the trimmed code is empty
   */
  public Sku {
    code = code.trim();
    if (code.isEmpty()) {
      throw new InvalidOrderException("sku code must be non-empty");
    }
  }
}
