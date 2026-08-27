package com.warehouse.domain

/**
 * A non-negative amount in integer minor units of a single currency.
 *
 * Currency codes are ISO-style (`^[A-Z]{3}$`), not ISO-4217 membership. `ZZZ` is
 * valid. Cross-currency operations raise [InvalidOrderException].
 */
data class Money(
    val minorUnits: Long,
    val currency: String
) {
    init {
        if (minorUnits < 0) {
            throw InvalidOrderException("money amount must be non-negative, got $minorUnits")
        }
        if (minorUnits > MAX_MINOR_UNITS) {
            throw InvalidOrderException(
                "money amount exceeds $MAX_MINOR_UNITS, got $minorUnits"
            )
        }
        if (!CURRENCY.matches(currency)) {
            throw InvalidOrderException(
                "currency must be a 3-letter uppercase ISO-style code, got $currency"
            )
        }
    }

    /** Returns the sum of two amounts of the same currency. */
    fun add(other: Money): Money {
        requireSameCurrency(other)
        if (other.minorUnits > MAX_MINOR_UNITS - minorUnits) {
            throw InvalidOrderException("money addition overflows the shared maximum")
        }
        return Money(Math.addExact(minorUnits, other.minorUnits), currency)
    }

    /** Returns this amount scaled by a non-negative integer multiplier. */
    fun times(multiplier: Int): Money {
        if (multiplier < 0) {
            throw InvalidOrderException("multiplier must be non-negative, got $multiplier")
        }
        try {
            val product = Math.multiplyExact(minorUnits, multiplier.toLong())
            if (product > MAX_MINOR_UNITS) {
                throw InvalidOrderException("money scaling overflows the shared maximum")
            }
            return Money(product, currency)
        } catch (overflow: ArithmeticException) {
            throw InvalidOrderException("money scaling overflows the shared maximum", overflow)
        }
    }

    private fun requireSameCurrency(other: Money) {
        if (currency != other.currency) {
            throw InvalidOrderException("currency mismatch: $currency vs ${other.currency}")
        }
    }

    companion object {
        /** Inclusive maximum minor units shared with every language pack. */
        const val MAX_MINOR_UNITS: Long = 9_007_199_254_740_991L
        private val CURRENCY = Regex("^[A-Z]{3}$")
    }
}
