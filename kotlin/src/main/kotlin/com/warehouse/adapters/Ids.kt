package com.warehouse.adapters

import com.warehouse.application.OrderIdGenerator
import com.warehouse.domain.OrderId
import java.util.concurrent.atomic.AtomicInteger

/** Test double that issues `ord-1`, `ord-2`, ... */
class SequenceOrderIdGenerator(
    private val prefix: String = "ord"
) : OrderIdGenerator {
    private val n = AtomicInteger(0)

    override fun next(): OrderId = OrderId("$prefix-${n.incrementAndGet()}")
}

/** Test double that always returns the same injected identifier. */
class FixedOrderIdGenerator(
    private val orderId: OrderId
) : OrderIdGenerator {
    override fun next(): OrderId = orderId
}
