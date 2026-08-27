package com.warehouse.domain

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

/** Sku invariant tests: ASCII-edge stripping, case, and UTF-8 byte length. */
class SkuTest {
    @ParameterizedTest
    @ValueSource(strings = ["", "   ", "\t\n", " \r "])
    fun rejectsCodesEmptyAfterTrimming(blank: String) {
        val error = assertThrows<InvalidOrderException> { Sku(blank) }
        assertEquals(true, error.message!!.contains("non-empty"))
    }

    @Test
    fun stripsOnlyAsciiSpaceTabCrLf() {
        assertEquals("SKU-42", Sku(" \t\r\nSKU-42 \t\r\n").code)
    }

    @Test
    fun keepsInteriorSpacingIntact() {
        assertEquals("SKU 42", Sku("SKU 42").code)
    }

    @Test
    fun preservesCase() {
        assertEquals("sku-a", Sku("sku-a").code)
        assertNotEquals(Sku("sku-a"), Sku("SKU-A"))
    }

    @Test
    fun preservesNbspPrefix() {
        assertEquals("\u00a0ABC", Sku("\u00a0ABC").code)
    }

    @Test
    fun acceptsMaxUtf8Bytes() {
        assertEquals(Sku.MAX_UTF8_BYTES, Sku("A".repeat(Sku.MAX_UTF8_BYTES)).code.length)
    }

    @Test
    fun rejectsAboveUtf8ByteLimit() {
        val error = assertThrows<InvalidOrderException> { Sku("A".repeat(Sku.MAX_UTF8_BYTES + 1)) }
        assertEquals(true, error.message!!.contains("UTF-8 bytes"))
    }
}
