package com.warehouse.domain

import java.nio.charset.StandardCharsets

/**
 * A stock-keeping-unit code, normalized to its trimmed form on creation.
 *
 * Only ASCII space, tab, CR, and LF are stripped from the ends. Interior text
 * and case are preserved. The UTF-8 byte length of the normalized code is at
 * most [MAX_UTF8_BYTES].
 */
@ConsistentCopyVisibility
data class Sku private constructor(
    val code: String
) {
    companion object {
        /** Inclusive UTF-8 byte-length limit of a normalized SKU code. */
        const val MAX_UTF8_BYTES: Int = 64

        operator fun invoke(code: String): Sku {
            val trimmed = stripAsciiEdges(code)
            if (trimmed.isEmpty()) {
                throw InvalidOrderException("sku code must be non-empty")
            }
            val utf8Bytes = trimmed.toByteArray(StandardCharsets.UTF_8).size
            if (utf8Bytes > MAX_UTF8_BYTES) {
                throw InvalidOrderException("sku code exceeds $MAX_UTF8_BYTES UTF-8 bytes")
            }
            return Sku(trimmed)
        }

        private fun stripAsciiEdges(raw: String): String {
            var start = 0
            var end = raw.length
            while (start < end && isEdgeWhitespace(raw[start])) {
                start++
            }
            while (end > start && isEdgeWhitespace(raw[end - 1])) {
                end--
            }
            return raw.substring(start, end)
        }

        private fun isEdgeWhitespace(c: Char): Boolean = c == ' ' || c == '\t' || c == '\r' || c == '\n'
    }
}
