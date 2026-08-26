package com.warehouse.domain;

/**
 * An amount of stock that must be strictly positive.
 *
 * @param value the counted amount; strictly positive
 */
public record Quantity(int value) {

  /**
   * Validates the strictly-positive invariant.
   *
   * @throws InvalidOrderException when {@code value} is zero or negative
   */
  public Quantity {
    if (value <= 0) {
      throw new InvalidOrderException("quantity must be strictly positive, got " + value);
    }
  }
}
