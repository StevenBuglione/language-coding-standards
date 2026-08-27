package com.warehouse.adapters

import com.warehouse.application.OrderRepository
import com.warehouse.application.OrderRepository.IdempotencyRecord
import com.warehouse.application.OrderRepository.SaveOutcome
import com.warehouse.domain.Order
import com.warehouse.domain.OrderId
import com.warehouse.domain.PersistenceConflictError
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * [OrderRepository] double keeping snapshots, never aliases, for tests and demos.
 *
 * Saves use compare-and-set on the optimistic version. Gets and idempotency
 * lookups return detached copies so a caller cannot mutate stored state.
 */
class InMemoryOrderRepository : OrderRepository {
    private val lock = ReentrantLock()
    private val orders = HashMap<OrderId, Order>()
    private val byKey = HashMap<String, IdempotencyRecord>()
    private val savedOrders = ArrayList<Order>()
    private var failSave: Boolean = false

    fun failSave(fail: Boolean) {
        lock.withLock { failSave = fail }
    }

    override fun save(
        order: Order,
        expectedVersion: Int
    ): SaveOutcome {
        return lock.withLock {
            if (failSave) {
                return@withLock SaveOutcome.Conflict(
                    PersistenceConflictError("forced save failure for ${order.id.value}")
                )
            }
            val current = orders[order.id]
            val currentVersion = current?.version ?: 0
            if (currentVersion != expectedVersion) {
                return@withLock SaveOutcome.Conflict(
                    PersistenceConflictError(
                        "version conflict for ${order.id.value}: " +
                            "expected $expectedVersion, stored $currentVersion"
                    )
                )
            }
            val stored = order.snapshot()
            stored.bumpVersion()
            orders[order.id] = stored
            val returned = stored.snapshot()
            savedOrders.add(returned.snapshot())
            SaveOutcome.Saved(returned)
        }
    }

    override fun get(orderId: OrderId): Order? = lock.withLock { orders[orderId]?.snapshot() }

    override fun getByIdempotencyKey(key: String): IdempotencyRecord? {
        return lock.withLock {
            val found = byKey[key] ?: return@withLock null
            IdempotencyRecord(found.fingerprint, found.order.snapshot())
        }
    }

    override fun rememberIdempotency(
        key: String,
        fingerprint: String,
        order: Order
    ) {
        lock.withLock {
            byKey[key] = IdempotencyRecord(fingerprint, order.snapshot())
        }
    }

    fun saved(): List<Order> = lock.withLock { savedOrders.toList() }
}
