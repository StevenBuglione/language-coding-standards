package com.warehouse.application

import com.warehouse.domain.CompensationFailureError
import com.warehouse.domain.InsufficientStockError
import com.warehouse.domain.Order
import com.warehouse.domain.OrderId
import com.warehouse.domain.OrderLine
import com.warehouse.domain.PaymentDeclinedError
import com.warehouse.domain.PersistenceConflictError

/** Outbound port that mints order identifiers. The domain never reads randomness. */
fun interface OrderIdGenerator {
    fun next(): OrderId
}

/**
 * Outbound port for atomic stock reservation.
 *
 * Every fallible outcome is a typed result value; implementations never raise
 * to report a business failure.
 */
interface InventoryGateway {
    data class ReservationToken(
        val orderId: OrderId,
        val idempotencyKey: String
    )

    fun reserveAll(
        orderId: OrderId,
        lines: List<OrderLine>,
        idempotencyKey: String
    ): ReservationOutcome

    fun release(token: ReservationToken): ReleaseOutcome

    sealed interface ReservationOutcome {
        data class Reserved(
            val token: ReservationToken
        ) : ReservationOutcome

        data class Shortage(
            val error: InsufficientStockError
        ) : ReservationOutcome
    }

    sealed interface ReleaseOutcome {
        data object Released : ReleaseOutcome

        data class Failed(
            val error: CompensationFailureError
        ) : ReleaseOutcome
    }
}

/**
 * Outbound port for collecting payment on the payments edge.
 *
 * Refusal is a typed result, never an exception.
 */
interface PaymentProcessor {
    data class ChargeReceipt(
        val orderId: OrderId,
        val idempotencyKey: String
    )

    fun charge(
        order: Order,
        idempotencyKey: String
    ): ChargeOutcome

    fun refund(receipt: ChargeReceipt): RefundOutcome

    sealed interface ChargeOutcome {
        data class Charged(
            val receipt: ChargeReceipt
        ) : ChargeOutcome

        data class Declined(
            val error: PaymentDeclinedError
        ) : ChargeOutcome
    }

    sealed interface RefundOutcome {
        data object Refunded : RefundOutcome

        data class Failed(
            val error: CompensationFailureError
        ) : RefundOutcome
    }
}

/**
 * Outbound port that persists and retrieves immutable snapshots.
 *
 * Reads and writes never expose a mutable alias to stored state.
 */
interface OrderRepository {
    data class IdempotencyRecord(
        val fingerprint: String,
        val order: Order
    )

    fun save(
        order: Order,
        expectedVersion: Int
    ): SaveOutcome

    fun get(orderId: OrderId): Order?

    fun getByIdempotencyKey(key: String): IdempotencyRecord?

    fun rememberIdempotency(
        key: String,
        fingerprint: String,
        order: Order
    )

    sealed interface SaveOutcome {
        data class Saved(
            val snapshot: Order
        ) : SaveOutcome

        data class Conflict(
            val error: PersistenceConflictError
        ) : SaveOutcome
    }
}
