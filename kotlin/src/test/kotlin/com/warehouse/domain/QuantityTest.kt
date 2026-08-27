package com.warehouse.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/** Quantity invariant tests: strict positivity within the shared int range. */
class QuantityTest {
    @ParameterizedTest
    @ValueSource(ints = [0, -1, -100])
    fun rejectsZeroAndNegativeAmounts(invalid: Int) {
        val error = assertThrows<InvalidOrderException> { Quantity(invalid) }
        assertEquals(true, error.message!!.contains("strictly positive"))
    }

    @ParameterizedTest
    @ValueSource(ints = [1, 7, 1_000_000, Int.MAX_VALUE])
    fun acceptsStrictlyPositiveAmounts(valid: Int) {
        assertEquals(valid, Quantity(valid).value)
    }

    @Test
    fun sharedMaximumIsIntegerMaxValue() {
        assertEquals(2_147_483_647, Quantity(Int.MAX_VALUE).value)
    }
}
