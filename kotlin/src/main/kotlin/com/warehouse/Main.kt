package com.warehouse

import com.warehouse.domain.Money

fun main() {
    val money = Money(0L, "ZZZ")
    require(money.currency == "ZZZ") { "ISO-style ZZZ must be a valid currency" }
    require(money.minorUnits == 0L) { "zero minor units must be accepted" }
    println("warehouse-ok ${money.currency}")
}
