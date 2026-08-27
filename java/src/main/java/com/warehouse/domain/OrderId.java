package com.warehouse.domain;

/**
 * Immutable unique identifier of an order, injected by the application.
 *
 * @param value non-blank identifier; never generated inside the domain
 */
public record OrderId(String value) {

  /**
   * Rejects empty or whitespace-only identifiers.
   *
   * @throws InvalidOrderException when {@code value} is blank
   */
  public OrderId {
    if (value.isBlank()) {
      throw new InvalidOrderException("order id must be non-empty");
    }
  }
}
