package com.warehouse.domain;

import java.io.Serial;

/**
 * Raised by the pure domain layer when a value or order violates a structural invariant.
 *
 * <p>Internal signaling only: {@code PlaceOrderUseCase} catches it and maps it to a typed {@link
 * DomainError.InvalidOrderError} payload, so no exception ever crosses the application boundary.
 */
public final class InvalidOrderException extends RuntimeException {

  @Serial private static final long serialVersionUID = 1L;

  /**
   * Creates the exception with a human-readable reason.
   *
   * @param message what invariant was violated and with which input
   */
  public InvalidOrderException(String message) {
    super(message);
  }
}
