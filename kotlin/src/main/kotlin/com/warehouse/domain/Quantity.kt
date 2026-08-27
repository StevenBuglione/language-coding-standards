package com.warehouse.domain

/**
 * An amount of stock that must be strictly positive.
 *
 * The shared range is `1` through [Int.MAX_VALUE] inclusive; Kotlin `Int` cannot
 * represent a larger value, so the upper bound is enforced by the type.
 */
data class Quantity(
    val value: Int
) {
    init {
        if (value <= 0) {
            throw InvalidOrderException("quantity must be strictly positive, got $value")
        }
    }
}
