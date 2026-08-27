package com.warehouse.adapters

import com.warehouse.application.InventoryGateway
import com.warehouse.application.InventoryGateway.ReleaseOutcome
import com.warehouse.application.InventoryGateway.ReservationOutcome
import com.warehouse.application.InventoryGateway.ReservationToken
import com.warehouse.domain.CompensationFailureError
import com.warehouse.domain.InsufficientStockError
import com.warehouse.domain.OrderId
import com.warehouse.domain.OrderLine
import com.warehouse.domain.Sku
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * [InventoryGateway] double enforcing a finite stock map, for tests and demos.
 *
 * `reserveAll` is atomic: every line is covered or none are. Concurrent callers
 * serialize on an internal lock so two reservations cannot oversell the last units.
 */
class InMemoryInventoryGateway(
    initialStock: Map<Sku, Int> = emptyMap()
) : InventoryGateway {
    private data class Held(
        val sku: Sku,
        val amount: Int
    )

    private val lock = ReentrantLock()
    private val stock = HashMap(initialStock)
    private val reservations = HashMap<String, List<Held>>()
    private var failRelease: Boolean = false

    fun failRelease(fail: Boolean) {
        lock.withLock { failRelease = fail }
    }

    fun snapshotStock(): Map<Sku, Int> = lock.withLock { stock.toMap() }

    override fun reserveAll(
        orderId: OrderId,
        lines: List<OrderLine>,
        idempotencyKey: String
    ): ReservationOutcome {
        return lock.withLock {
            if (idempotencyKey in reservations) {
                return@withLock ReservationOutcome.Reserved(
                    ReservationToken(orderId, idempotencyKey)
                )
            }
            for (line in lines) {
                val available = stock[line.sku] ?: 0
                if (available < line.quantity.value) {
                    return@withLock ReservationOutcome.Shortage(
                        InsufficientStockError(line.sku, line.quantity, available)
                    )
                }
            }
            val held = ArrayList<Held>(lines.size)
            for (line in lines) {
                val available = stock[line.sku] ?: 0
                stock[line.sku] = available - line.quantity.value
                held.add(Held(line.sku, line.quantity.value))
            }
            reservations[idempotencyKey] = held
            ReservationOutcome.Reserved(ReservationToken(orderId, idempotencyKey))
        }
    }

    override fun release(token: ReservationToken): ReleaseOutcome {
        return lock.withLock {
            if (failRelease) {
                return@withLock ReleaseOutcome.Failed(
                    CompensationFailureError("release", "forced failure")
                )
            }
            val held = reservations.remove(token.idempotencyKey)
            if (held != null) {
                for (item in held) {
                    stock[item.sku] = (stock[item.sku] ?: 0) + item.amount
                }
            }
            ReleaseOutcome.Released
        }
    }
}
