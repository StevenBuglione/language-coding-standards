package com.warehouse.property

import com.warehouse.domain.Money
import io.kotest.property.Arb
import io.kotest.property.arbitrary.long
import io.kotest.property.checkAll
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Test

class MoneyPropertyTest {
    @Test
    fun additionIsCommutative() {
        runBlocking {
            checkAll(Arb.long(0L..1_000_000L), Arb.long(0L..1_000_000L)) { left, right ->
                val a = Money(left, "USD")
                val b = Money(right, "USD")
                require(a.add(b) == b.add(a))
            }
        }
    }

    @Test
    fun scalingByZeroIsZero() {
        runBlocking {
            checkAll(Arb.long(0L..1_000_000L)) { amount ->
                val money = Money(amount, "EUR")
                require(money.times(0) == Money(0, "EUR"))
            }
        }
    }
}
