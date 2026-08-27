package com.warehouse.adapters

import com.warehouse.application.PaymentProcessor
import com.warehouse.application.PaymentProcessor.ChargeOutcome
import com.warehouse.application.PaymentProcessor.ChargeReceipt
import com.warehouse.application.PaymentProcessor.RefundOutcome
import com.warehouse.domain.CompensationFailureError
import com.warehouse.domain.Order
import com.warehouse.domain.PaymentDeclinedError
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * [PaymentProcessor] double with a configurable decline switch, for tests and demos.
 *
 * Every charge attempt is recorded so tests can prove whether collection was
 * attempted at all. Identical idempotency keys replay the original outcome
 * without a second charge.
 */
class FakePaymentProcessor(
    private val decline: Boolean = false
) : PaymentProcessor {
    private val lock = ReentrantLock()
    private val chargedOrders = ArrayList<Order>()
    private val refundedReceipts = ArrayList<ChargeReceipt>()
    private val outcomes = HashMap<String, ChargeOutcome>()
    private var failRefund: Boolean = false

    fun failRefund(fail: Boolean) {
        lock.withLock { failRefund = fail }
    }

    override fun charge(
        order: Order,
        idempotencyKey: String
    ): ChargeOutcome {
        return lock.withLock {
            val existing = outcomes[idempotencyKey]
            if (existing != null) {
                return@withLock existing
            }
            chargedOrders.add(order)
            if (decline) {
                val declined =
                    ChargeOutcome.Declined(
                        PaymentDeclinedError("payment declined for order ${order.id.value}")
                    )
                outcomes[idempotencyKey] = declined
                return@withLock declined
            }
            val receipt = ChargeReceipt(order.id, idempotencyKey)
            val charged = ChargeOutcome.Charged(receipt)
            outcomes[idempotencyKey] = charged
            charged
        }
    }

    override fun refund(receipt: ChargeReceipt): RefundOutcome {
        return lock.withLock {
            if (failRefund) {
                return@withLock RefundOutcome.Failed(
                    CompensationFailureError("refund", "forced failure")
                )
            }
            refundedReceipts.add(receipt)
            RefundOutcome.Refunded
        }
    }

    fun chargedOrders(): List<Order> = lock.withLock { chargedOrders.toList() }

    fun refunded(): List<ChargeReceipt> = lock.withLock { refundedReceipts.toList() }
}
