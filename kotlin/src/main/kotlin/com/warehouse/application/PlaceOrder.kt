package com.warehouse.application

import com.warehouse.application.InventoryGateway.ReleaseOutcome
import com.warehouse.application.InventoryGateway.ReservationOutcome
import com.warehouse.application.InventoryGateway.ReservationToken
import com.warehouse.application.OrderRepository.IdempotencyRecord
import com.warehouse.application.OrderRepository.SaveOutcome
import com.warehouse.application.PaymentProcessor.ChargeOutcome
import com.warehouse.application.PaymentProcessor.ChargeReceipt
import com.warehouse.application.PaymentProcessor.RefundOutcome
import com.warehouse.domain.DomainError
import com.warehouse.domain.InvalidOrderError
import com.warehouse.domain.InvalidOrderException
import com.warehouse.domain.Order
import com.warehouse.domain.OrderLine

/**
 * Typed outcome of placing an order.
 *
 * No exception crosses the use-case boundary: every execution returns a
 * [Success] carrying the persisted PAID snapshot or a [Failure] carrying
 * exactly one sealed [DomainError] payload.
 */
sealed interface PlaceOrderResult {
    data class Success(
        val order: Order
    ) : PlaceOrderResult

    data class Failure(
        val error: DomainError
    ) : PlaceOrderResult
}

/**
 * Orchestrates validate -> reserveAll -> charge -> pay -> persist, with compensation.
 */
class PlaceOrderUseCase(
    private val inventory: InventoryGateway,
    private val payments: PaymentProcessor,
    private val repository: OrderRepository,
    private val ids: OrderIdGenerator
) {
    fun execute(
        lines: List<OrderLine>,
        idempotencyKey: String
    ): PlaceOrderResult {
        val remembered = repository.getByIdempotencyKey(idempotencyKey)
        if (remembered != null) {
            return replay(remembered, lines)
        }
        return placeNew(lines, idempotencyKey)
    }

    private fun replay(
        remembered: IdempotencyRecord,
        lines: List<OrderLine>
    ): PlaceOrderResult {
        if (remembered.fingerprint != fingerprint(lines)) {
            return PlaceOrderResult.Failure(
                InvalidOrderError("idempotency key reused with different payload")
            )
        }
        return PlaceOrderResult.Success(remembered.order)
    }

    private fun placeNew(
        lines: List<OrderLine>,
        idempotencyKey: String
    ): PlaceOrderResult {
        val order =
            try {
                Order(ids.next(), lines)
            } catch (error: InvalidOrderException) {
                return PlaceOrderResult.Failure(
                    InvalidOrderError(error.message ?: "invalid order")
                )
            }
        return when (val reserved = inventory.reserveAll(order.id, order.lines, idempotencyKey)) {
            is ReservationOutcome.Shortage -> PlaceOrderResult.Failure(reserved.error)
            is ReservationOutcome.Reserved ->
                chargeAndPersist(order, idempotencyKey, reserved.token, lines)
        }
    }

    private fun chargeAndPersist(
        order: Order,
        idempotencyKey: String,
        token: ReservationToken,
        lines: List<OrderLine>
    ): PlaceOrderResult =
        when (val charged = payments.charge(order, idempotencyKey)) {
            is ChargeOutcome.Declined -> releaseOrFail(token, charged.error)
            is ChargeOutcome.Charged ->
                payAndSave(order, idempotencyKey, fingerprint(lines), token, charged.receipt)
        }

    private fun payAndSave(
        order: Order,
        idempotencyKey: String,
        fingerprint: String,
        token: ReservationToken,
        receipt: ChargeReceipt
    ): PlaceOrderResult {
        order.pay()
        return when (val saved = repository.save(order, 0)) {
            is SaveOutcome.Conflict -> compensate(token, receipt, saved.error)
            is SaveOutcome.Saved -> {
                repository.rememberIdempotency(idempotencyKey, fingerprint, saved.snapshot)
                PlaceOrderResult.Success(saved.snapshot)
            }
        }
    }

    private fun compensate(
        token: ReservationToken,
        receipt: ChargeReceipt,
        original: DomainError
    ): PlaceOrderResult =
        when (val refunded = payments.refund(receipt)) {
            is RefundOutcome.Failed -> PlaceOrderResult.Failure(refunded.error)
            is RefundOutcome.Refunded -> releaseOrFail(token, original)
        }

    private fun releaseOrFail(
        token: ReservationToken,
        original: DomainError
    ): PlaceOrderResult =
        when (val released = inventory.release(token)) {
            is ReleaseOutcome.Failed -> PlaceOrderResult.Failure(released.error)
            is ReleaseOutcome.Released -> PlaceOrderResult.Failure(original)
        }

    companion object {
        internal fun fingerprint(lines: List<OrderLine>): String =
            lines.joinToString("|") { line ->
                "${line.sku.code}:${line.quantity.value}:" +
                    "${line.unitPrice.currency}:${line.unitPrice.minorUnits}"
            }
    }
}
