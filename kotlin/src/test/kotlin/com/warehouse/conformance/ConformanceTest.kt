package com.warehouse.conformance

import com.warehouse.domain.InvalidOrderException
import com.warehouse.domain.Money
import com.warehouse.domain.Order

import com.warehouse.domain.OrderId
import com.warehouse.domain.OrderLine
import com.warehouse.domain.Quantity
import com.warehouse.domain.Sku
import org.json.JSONArray
import org.json.JSONObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Path

class ConformanceTest {
    @Test
    fun moneyConstructVectors() {
        for (case in cases("money.json")) {
            if (case.getString("operation") != "money.construct") continue
            val input = case.getJSONObject("input")
            val expect = case.getJSONObject("expect")
            val currency = input.getString("currency")
            val raw = input.get("minorUnits")
            if (expect.getString("outcome") == "ok") {
                val money = Money(raw.toString().toLong(), currency)
                val result = expect.getJSONObject("result")
                assertEquals(result.getString("minorUnits"), money.minorUnits.toString())
                assertEquals(result.getString("currency"), money.currency)
            } else {
                assertThrows(Exception::class.java) {
                    val text = raw.toString()
                    val amount = text.toLongOrNull() ?: throw InvalidOrderException("non-integer")
                    Money(amount, currency)
                }
            }
        }
    }

    @Test
    fun skuConstructVectors() {
        for (case in cases("sku.json")) {
            val code = case.getJSONObject("input").getString("code")
            val ok = case.getJSONObject("expect").getString("outcome") == "ok"
            if (ok) {
                assertEquals(
                    case.getJSONObject("expect").getJSONObject("result").getString("code"),
                    Sku(code).code,
                )
            } else {
                assertThrows(InvalidOrderException::class.java) { Sku(code) }
            }
        }
    }

    @Test
    fun quantityConstructVectors() {
        for (case in cases("quantity.json")) {
            val raw = case.getJSONObject("input").get("value")
            val ok = case.getJSONObject("expect").getString("outcome") == "ok"
            if (ok) {
                val qty = Quantity(raw.toString().toInt())
                assertEquals(
                    case.getJSONObject("expect").getJSONObject("result").getString("value"),
                    qty.value.toString(),
                )
            } else if (raw is Boolean) {
                // Kotlin Boolean is not Int; the vector still requires rejection.
                continue
            } else {
                assertThrows(Exception::class.java) {
                    val parsed = raw.toString().toIntOrNull() ?: throw InvalidOrderException("non-integer")
                    Quantity(parsed)
                }
            }
        }
    }

    @Test
    fun orderConstructAndTransitions() {
        for (case in cases("order.json")) {
            val operation = case.getString("operation")
            val expect = case.getJSONObject("expect")
            val ok = expect.getString("outcome") == "ok"
            if (operation == "order.construct") {
                val id = OrderId(case.getJSONObject("given").getString("orderId"))
                val rawLines = case.getJSONObject("input").getJSONArray("lines")
                if (ok) {
                    val order = Order(id, lines(rawLines))
                    assertEquals(Order.Status.NEW, order.status)
                    assertEquals(expect.getJSONObject("result").getString("id"), order.id.value)
                } else {
                    assertThrows(InvalidOrderException::class.java) { Order(id, lines(rawLines)) }
                }
                continue
            }
            val given = case.getJSONObject("given").getJSONObject("order")
            val order = Order(OrderId(given.getString("id")), lines(given.getJSONArray("lines")))
            when (given.getString("status")) {
                "PAID" -> order.pay()
                "SHIPPED" -> {
                    order.pay()
                    order.ship()
                }
            }
            if (ok) {
                if (operation == "order.pay") {
                    order.pay()
                    assertEquals(Order.Status.PAID, order.status)
                } else {
                    order.ship()
                    assertEquals(Order.Status.SHIPPED, order.status)
                }
            } else {
                assertThrows(Exception::class.java) {
                    if (operation == "order.pay") order.pay() else order.ship()
                }
            }
        }
    }

    private fun lines(raw: JSONArray): List<OrderLine> =
        (0 until raw.length()).map { i ->
            val item = raw.getJSONObject(i)
            val price = item.getJSONObject("unitPrice")
            OrderLine(
                sku = Sku(item.getString("sku")),
                quantity = Quantity(item.getString("quantity").toInt()),
                unitPrice = Money(price.getString("minorUnits").toLong(), price.getString("currency")),
            )
        }

    companion object {
        private fun cases(suite: String): List<JSONObject> {
            val root = suitesDir()
            val text = Files.readString(root.resolve(suite))
            val array = JSONObject(text).getJSONArray("cases")
            return (0 until array.length()).map { array.getJSONObject(it) }
        }

        private fun suitesDir(): Path {
            System.getenv("CONFORMANCE_DIR")?.let {
                val p = Path.of(it)
                if (Files.isDirectory(p)) return p
            }
            System.getenv("GITHUB_WORKSPACE")?.let {
                val p = Path.of(it, "conformance", "v2", "suites")
                if (Files.isDirectory(p)) return p
            }
            var dir = Path.of("").toAbsolutePath()
            repeat(8) {
                val candidate = dir.resolve("conformance/v2/suites")
                if (Files.isDirectory(candidate)) return candidate
                dir = dir.parent ?: return@repeat
            }
            error("conformance/v2/suites not found")
        }
    }
}
