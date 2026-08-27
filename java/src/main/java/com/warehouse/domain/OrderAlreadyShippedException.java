package com.warehouse.domain;

import java.io.Serial;

/**
 * Raised by {@link Order} when an already-shipped order is mutated.
 *
 * <p>Internal signaling only: shipped orders are terminal, and every legal pipeline keeps this from
 * escaping the use case.
 */
public final class OrderAlreadyShippedException extends RuntimeException {

  @Serial private static final long serialVersionUID = 1L;

  /**
   * Creates the exception with a human-readable reason.
   *
   * @param message which order was mutated after shipping
   */
  public OrderAlreadyShippedException(String message) {
    super(message);
  }
}
