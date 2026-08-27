package com.warehouse.domain

/**
 * Sealed vocabulary of recoverable domain-rule violations.
 *
 * Instances of these payloads — never exceptions — cross the use-case boundary
 * inside [com.warehouse.application.PlaceOrderResult.Failure].
 */
sealed interface DomainError

/** An order or value violates a structural domain invariant. */
data class InvalidOrderError(
    val reason: String
) : DomainError

/** The inventory could not cover the requested quantity for a SKU. */
data class InsufficientStockError(
    val sku: Sku,
    val requested: Quantity,
    val available: Int
) : DomainError

/** The payment processor refused to charge the order. */
data class PaymentDeclinedError(
    val reason: String
) : DomainError

/** An optimistic save lost a compare-and-set race. */
data class PersistenceConflictError(
    val reason: String
) : DomainError

/** An adapter failed with a stage and retryability. */
data class InfrastructureFailureError(
    val stage: String,
    val retryable: Boolean,
    val detail: String
) : DomainError

/** Refund or reservation release failed after a partial success. */
data class CompensationFailureError(
    val stage: String,
    val detail: String
) : DomainError

/** A shipped order can no longer be mutated. */
data class OrderAlreadyShippedError(
    val orderId: OrderId
) : DomainError

/**
 * Raised by the pure domain layer when a value or order violates a structural invariant.
 *
 * Internal signaling only: the use case maps it to [InvalidOrderError].
 */
class InvalidOrderException(
    message: String,
    cause: Throwable? = null
) : RuntimeException(message, cause)

/**
 * Raised by [Order] when an already-shipped order is mutated.
 *
 * Internal signaling only: shipped orders are terminal.
 */
class OrderAlreadyShippedException(
    message: String
) : RuntimeException(message)
