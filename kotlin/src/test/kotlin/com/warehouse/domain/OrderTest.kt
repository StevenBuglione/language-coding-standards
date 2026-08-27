package com.warehouse.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

/** Order invariant and state-machine tests. */
class OrderTest {
    @Test
    fun rejectsEmptyLineSets() {
        val error = assertThrows<InvalidOrderException> { Order(id(), emptyList()) }
        assertEquals(true, error.message!!.contains("at least one line"))
    }

    @Test
    fun rejectsBlankOrderId() {
        val error = assertThrows<InvalidOrderException> { OrderId(" ") }
        assertEquals(true, error.message!!.contains("order id"))
    }

    @Test
    fun rejectsDuplicateSkusAcrossLines() {
        val lines = listOf(line("SKU-1", 1, 500), line("SKU-1", 2, 500))
        val error = assertThrows<InvalidOrderException> { Order(id(), lines) }
        assertEquals(true, error.message!!.contains("duplicate SKUs"))
    }

    @Test
    fun rejectsDuplicateSkusAfterNormalization() {
        val lines = listOf(line("SKU-1", 1, 500), line(" SKU-1 ", 2, 500))
        val error = assertThrows<InvalidOrderException> { Order(id(), lines) }
        assertEquals(true, error.message!!.contains("duplicate SKUs"))
    }

    @Test
    fun computesTotalAsSumOfLineTotals() {
        val placed = order(line("SKU-1", 2, 500), line("SKU-2", 3, 250))
        assertEquals(Money(1750, USD), placed.total())
    }

    @Test
    fun rejectsMixedCurrenciesAtConstruction() {
        val mixed =
            listOf(
                OrderLine(Sku("SKU-1"), Quantity(1), Money(500, USD)),
                OrderLine(Sku("SKU-2"), Quantity(1), Money(500, "EUR"))
            )
        val error = assertThrows<InvalidOrderException> { Order(id(), mixed) }
        assertEquals(true, error.message!!.contains("mixed currencies"))
    }

    @Test
    fun usesInjectedIdAndStartsNewAtVersionZero() {
        val placed = Order(OrderId("ord-fixed-9"), listOf(line("SKU-1", 1, 500)))
        assertEquals(Order.Status.NEW, placed.status)
        assertEquals("ord-fixed-9", placed.id.value)
        assertEquals(0, placed.version)
    }

    @Test
    fun exposesAnImmutableLineList() {
        val placed = order(line("SKU-1", 1, 500))
        assertThrows<UnsupportedOperationException> {
            @Suppress("UNCHECKED_CAST")
            val mutable = placed.lines as MutableList<OrderLine>
            mutable.add(line("SKU-2", 1, 100))
        }
    }

    @Test
    fun snapshotIsDetachedFromTheOriginal() {
        val original = order(line("SKU-1", 1, 500))
        val copy = original.snapshot()
        copy.pay()
        copy.bumpVersion()
        assertEquals(Order.Status.NEW, original.status)
        assertEquals(0, original.version)
        assertEquals(Order.Status.PAID, copy.status)
        assertEquals(1, copy.version)
    }

    @Test
    fun paysNewOrderThenShipsPaidOrder() {
        val placed = order(line("SKU-1", 1, 500))
        placed.pay()
        assertEquals(Order.Status.PAID, placed.status)
        placed.ship()
        assertEquals(Order.Status.SHIPPED, placed.status)
    }

    @Test
    fun refusesToPayTwice() {
        val placed = order(line("SKU-1", 1, 500))
        placed.pay()
        val error = assertThrows<InvalidOrderException> { placed.pay() }
        assertEquals(true, error.message!!.contains("already been paid"))
    }

    @Test
    fun refusesToShipUnpaidOrders() {
        val placed = order(line("SKU-1", 1, 500))
        val error = assertThrows<InvalidOrderException> { placed.ship() }
        assertEquals(true, error.message!!.contains("paid"))
    }

    @Test
    fun refusesAnyMutationAfterShipping() {
        val placed = order(line("SKU-1", 1, 500))
        placed.pay()
        placed.ship()
        assertThrows<OrderAlreadyShippedException> { placed.pay() }
        assertThrows<OrderAlreadyShippedException> { placed.ship() }
    }

    companion object {
        private const val USD = "USD"

        private fun id(): OrderId = OrderId("ord-1")

        private fun line(
            sku: String,
            quantity: Int,
            minorUnits: Long
        ): OrderLine = OrderLine(Sku(sku), Quantity(quantity), Money(minorUnits, USD))

        private fun order(vararg lines: OrderLine): Order = Order(id(), lines.toList())
    }
}
