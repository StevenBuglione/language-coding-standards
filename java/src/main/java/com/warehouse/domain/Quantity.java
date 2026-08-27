package com.warehouse.domain;

/**
 * An amount of stock that must be strictly positive.
 *
 * <p>The shared range is {@code 1} through {@link Integer#MAX_VALUE} inclusive; Java {@code int}
 * cannot represent a larger value, so the upper bound is enforced by the type.
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
