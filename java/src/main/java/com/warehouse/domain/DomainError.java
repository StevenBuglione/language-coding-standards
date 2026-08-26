package com.warehouse.domain;

import java.util.UUID;

/**
 * Sealed hierarchy of recoverable domain-rule violations.
 *
 * <p>Instances of these payloads — never exceptions — cross the use-case boundary inside {@code
 * PlaceOrderResult.Failure}. The sealed permit list is exhaustive: a failure carries exactly one of
 * the three canonical domain errors, and javac rejects any fourth variant at compile time.
 */
public sealed interface DomainError
    permits DomainError.InsufficientStockError,
        DomainError.InvalidOrderError,
        DomainError.OrderAlreadyShippedError {

  /** The inventory could not cover the requested quantity for a SKU. */
  record InsufficientStockError(Sku sku, Quantity requested, int available)
      implements DomainError {}

  /** An order or value violates a structural domain invariant. */
  record InvalidOrderError(String reason) implements DomainError {}

  /** A shipped order can no longer be mutated. */
  record OrderAlreadyShippedError(UUID orderId) implements DomainError {}
}
