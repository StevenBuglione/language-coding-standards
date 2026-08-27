package com.warehouse.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/** Money invariant tests: non-negativity, ISO-style currency, overflow, scaling. */
class MoneyTest {
    @ParameterizedTest
    @ValueSource(longs = [-1, -500])
    fun rejectsNegativeAmounts(negative: Long) {
        val error = assertThrows<InvalidOrderException> { Money(negative, USD) }
        assertEquals(true, error.message!!.contains("non-negative"))
    }

    @Test
    fun acceptsZeroAndPositiveAmounts() {
        assertEquals(0L, Money(0, USD).minorUnits)
        assertEquals(1000L, Money(1000, USD).minorUnits)
    }

    @Test
    fun acceptsSharedMaximumAndIsoStyleZzz() {
        assertEquals(Money.MAX_MINOR_UNITS, Money(Money.MAX_MINOR_UNITS, USD).minorUnits)
        assertEquals("ZZZ", Money(0, "ZZZ").currency)
    }

    @Test
    fun rejectsAmountAboveSharedMaximum() {
        val error = assertThrows<InvalidOrderException> { Money(Money.MAX_MINOR_UNITS + 1, USD) }
        assertEquals(true, error.message!!.contains("exceeds"))
    }

    @ParameterizedTest
    @ValueSource(strings = ["usd", "US", "USDD", "", "US1"])
    fun rejectsMalformedCurrency(currency: String) {
        val error = assertThrows<InvalidOrderException> { Money(1, currency) }
        assertEquals(true, error.message!!.contains("currency"))
    }

    @Test
    fun addsAmountsOfSameCurrency() {
        val sum = Money(300, USD).add(Money(700, USD))
        assertEquals(Money(1000, USD), sum)
    }

    @Test
    fun rejectsCrossCurrencyAdditionAsInvalidOrder() {
        val dollars = Money(300, USD)
        val euros = Money(300, EUR)
        val error = assertThrows<InvalidOrderException> { dollars.add(euros) }
        assertEquals(true, error.message!!.contains("currency mismatch"))
    }

    @Test
    fun addRejectsOverflowOfSharedMaximum() {
        val max = Money(Money.MAX_MINOR_UNITS, USD)
        val error = assertThrows<InvalidOrderException> { max.add(Money(1, USD)) }
        assertEquals(true, error.message!!.contains("overflows"))
    }

    @Test
    fun scalesByNonNegativeMultiplier() {
        assertEquals(Money(1000, USD), Money(250, USD).times(4))
        assertEquals(Money(0, USD), Money(250, USD).times(0))
    }

    @Test
    fun rejectsNegativeMultiplier() {
        val error = assertThrows<InvalidOrderException> { Money(250, USD).times(-2) }
        assertEquals(true, error.message!!.contains("non-negative"))
    }

    @Test
    fun timesRejectsOverflowOfSharedMaximum() {
        val max = Money(Money.MAX_MINOR_UNITS, USD)
        val error = assertThrows<InvalidOrderException> { max.times(2) }
        assertEquals(true, error.message!!.contains("overflows"))
    }

    @Test
    fun timesRejectsLongOverflowAsInvalidOrder() {
        val max = Money(Money.MAX_MINOR_UNITS, USD)
        val error = assertThrows<InvalidOrderException> { max.times(Int.MAX_VALUE) }
        assertEquals(true, error.message!!.contains("overflows"))
    }

    @Test
    fun recordsWithSameFieldsAreEqual() {
        assertEquals(Money(500, USD), Money(500, USD))
        assertNotEquals(Money(500, USD), Money(501, USD))
        assertNotEquals(Money(500, USD), Money(500, EUR))
    }

    companion object {
        private const val USD = "USD"
        private const val EUR = "EUR"
    }
}
