package com.warehouse.domain;

/**
 * Sealed hierarchy of recoverable domain-rule violations.
 *
 * <p>Instances of these payloads — never exceptions — cross the use-case boundary inside {@code
 * PlaceOrderResult.Failure}. The sealed permit list is exhaustive: javac rejects an undeclared
 * variant at compile time.
 */
public sealed interface DomainError
    permits DomainError.CompensationFailureError,
        DomainError.InsufficientStockError,
        DomainError.InvalidOrderError,
        DomainError.OrderAlreadyShippedError,
        DomainError.PaymentDeclinedError,
        DomainError.PersistenceConflictError {

  /** Refund or reservation release failed after a partial success. */
  record CompensationFailureError(String stage, String detail) implements DomainError {}

  /** The inventory could not cover the requested quantity for a SKU. */
  record InsufficientStockError(Sku sku, Quantity requested, int available)
      implements DomainError {}

  /** An order or value violates a structural domain invariant. */
  record InvalidOrderError(String reason) implements DomainError {}

  /** A shipped order can no longer be mutated. */
  record OrderAlreadyShippedError(OrderId orderId) implements DomainError {}

  /** The payment processor refused to charge the order. */
  record PaymentDeclinedError(String reason) implements DomainError {}

  /** An optimistic save lost a compare-and-set race. */
  record PersistenceConflictError(String reason) implements DomainError {}
}
