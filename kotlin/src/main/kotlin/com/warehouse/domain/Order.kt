package com.warehouse.domain

/**
 * Immutable unique identifier of an order, injected by the application.
 */
data class OrderId(
    val value: String
) {
    init {
        if (value.isBlank()) {
            throw InvalidOrderException("order id must be non-empty")
        }
    }
}

/**
 * One SKU/quantity/unit-price row of an order.
 */
data class OrderLine(
    val sku: Sku,
    val quantity: Quantity,
    val unitPrice: Money
) {
    /** Returns the unit price scaled by the ordered quantity. */
    fun lineTotal(): Money = unitPrice.times(quantity.value)
}

/**
 * Order entity enforcing the canonical invariants.
 *
 * Invariants: injected id; at least one line; no duplicate normalized SKUs;
 * single currency at construction; the total always equals the checked sum of
 * line totals; only `NEW → PAID → SHIPPED` is legal.
 */
class Order private constructor(
    val id: OrderId,
    val lines: List<OrderLine>,
    status: Status,
    version: Int
) {
    /** States of the canonical order life cycle. */
    enum class Status {
        NEW,
        PAID,
        SHIPPED
    }

    var status: Status = status
        private set

    var version: Int = version
        private set

    companion object {
        operator fun invoke(
            id: OrderId,
            lines: List<OrderLine>
        ): Order {
            val snapshot = java.util.List.copyOf(lines)
            if (snapshot.isEmpty()) {
                throw InvalidOrderException("an order requires at least one line")
            }
            val distinctSkus = snapshot.map { it.sku.code }.toSet()
            if (distinctSkus.size != snapshot.size) {
                throw InvalidOrderException("duplicate SKUs across order lines are not allowed")
            }
            val currency = snapshot.first().unitPrice.currency
            for (line in snapshot) {
                if (line.unitPrice.currency != currency) {
                    throw InvalidOrderException("mixed currencies are not allowed")
                }
            }
            return Order(id, snapshot, Status.NEW, 0)
        }
    }

    /** Returns the sum of all line totals in the order's single currency. */
    fun total(): Money {
        var total = lines.first().lineTotal()
        for (line in lines.drop(1)) {
            total = total.add(line.lineTotal())
        }
        return total
    }

    /** Transitions NEW to PAID. */
    fun pay() {
        ensureNotShipped()
        if (status != Status.NEW) {
            throw InvalidOrderException("order has already been paid")
        }
        status = Status.PAID
    }

    /** Transitions PAID to SHIPPED; only paid orders may ship. */
    fun ship() {
        ensureNotShipped()
        if (status != Status.PAID) {
            throw InvalidOrderException("only paid orders can be shipped")
        }
        status = Status.SHIPPED
    }

    /**
     * Increments the optimistic version after a successful save.
     *
     * Called by the repository on a snapshot, never as a domain state transition.
     */
    fun bumpVersion() {
        version++
    }

    /** Returns a detached copy so repositories cannot alias stored state. */
    fun snapshot(): Order = Order(id, lines, status, version)

    private fun ensureNotShipped() {
        if (status == Status.SHIPPED) {
            throw OrderAlreadyShippedException("order ${id.value} has already shipped")
        }
    }
}
