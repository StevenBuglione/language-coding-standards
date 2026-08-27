package com.warehouse.application

import com.warehouse.adapters.FakePaymentProcessor
import com.warehouse.adapters.InMemoryInventoryGateway
import com.warehouse.adapters.InMemoryOrderRepository
import com.warehouse.application.InventoryGateway.ReleaseOutcome
import com.warehouse.application.InventoryGateway.ReservationOutcome
import com.warehouse.application.InventoryGateway.ReservationToken
import com.warehouse.application.OrderRepository.SaveOutcome
import com.warehouse.application.PaymentProcessor.ChargeOutcome
import com.warehouse.domain.CompensationFailureError
import com.warehouse.domain.InsufficientStockError
import com.warehouse.domain.InvalidOrderError
import com.warehouse.domain.Money
import com.warehouse.domain.Order
import com.warehouse.domain.OrderId
import com.warehouse.domain.OrderLine
import com.warehouse.domain.PaymentDeclinedError
import com.warehouse.domain.PersistenceConflictError
import com.warehouse.domain.Quantity
import com.warehouse.domain.Sku
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertNotSame
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicInteger

/**
 * Integration tests: the full place-order pipeline over in-memory adapters,
 * covering the happy path plus each failure path (CONTRACTS.md §2).
 */
class PlaceOrderUseCaseTest {
    @Test
    fun happyPathReservesChargesPaysAndPersistsPaid() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = false)

        val result = pipeline.useCase.execute(listOf(line("SKU-1", 2, 500)), "idem-1")

        val success = assertInstanceOf(PlaceOrderResult.Success::class.java, result)
        assertEquals(Order.Status.PAID, success.order.status)
        assertEquals("ord-1", success.order.id.value)
        assertEquals(Money(1000, USD), success.order.total())
        assertEquals(1, success.order.version)
        val stored = pipeline.repository.get(success.order.id)
        assertEquals(Order.Status.PAID, stored!!.status)
        assertNotSame(success.order, stored)
        assertEquals(1, pipeline.payments.chargedOrders().size)
        assertEquals(1, pipeline.repository.saved().size)
        assertEquals(8, pipeline.inventory.snapshotStock()[Sku("SKU-1")])
    }

    @Test
    fun insufficientStockFailsWithoutChargeOrPersist() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 1), decline = false)

        val result = pipeline.useCase.execute(listOf(line("SKU-1", 5, 500)), "idem-2")

        val failure = assertInstanceOf(PlaceOrderResult.Failure::class.java, result)
        val shortage = assertInstanceOf(InsufficientStockError::class.java, failure.error)
        assertEquals(1, shortage.available)
        assertTrue(pipeline.payments.chargedOrders().isEmpty())
        assertTrue(pipeline.repository.saved().isEmpty())
        assertEquals(1, pipeline.inventory.snapshotStock()[Sku("SKU-1")])
    }

    @Test
    fun paymentDeclineReleasesReservationWithoutPersist() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = true)

        val result = pipeline.useCase.execute(listOf(line("SKU-1", 1, 500)), "idem-3")

        val failure = assertInstanceOf(PlaceOrderResult.Failure::class.java, result)
        val declined = assertInstanceOf(PaymentDeclinedError::class.java, failure.error)
        assertTrue(declined.reason.contains("declined"))
        assertEquals(1, pipeline.payments.chargedOrders().size)
        assertTrue(pipeline.repository.saved().isEmpty())
        assertEquals(10, pipeline.inventory.snapshotStock()[Sku("SKU-1")])
    }

    @Test
    fun saveFailureRefundsAndReleases() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = false)
        pipeline.repository.failSave(true)

        val result = pipeline.useCase.execute(listOf(line("SKU-1", 1, 500)), "idem-4")

        val failure = assertInstanceOf(PlaceOrderResult.Failure::class.java, result)
        assertInstanceOf(PersistenceConflictError::class.java, failure.error)
        assertEquals(1, pipeline.payments.refunded().size)
        assertEquals(10, pipeline.inventory.snapshotStock()[Sku("SKU-1")])
        assertTrue(pipeline.repository.saved().isEmpty())
    }

    @Test
    fun compensationFailureAfterSaveFailure() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = false)
        pipeline.repository.failSave(true)
        pipeline.payments.failRefund(true)

        val result = pipeline.useCase.execute(listOf(line("SKU-1", 1, 500)), "idem-5")

        val failure = assertInstanceOf(PlaceOrderResult.Failure::class.java, result)
        assertInstanceOf(CompensationFailureError::class.java, failure.error)
    }

    @Test
    fun releaseFailureAfterSaveFailureIsCompensationFailure() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = false)
        pipeline.repository.failSave(true)
        pipeline.inventory.failRelease(true)

        val result = pipeline.useCase.execute(listOf(line("SKU-1", 1, 500)), "idem-5c")

        val failure = assertInstanceOf(PlaceOrderResult.Failure::class.java, result)
        assertInstanceOf(CompensationFailureError::class.java, failure.error)
        assertEquals(1, pipeline.payments.refunded().size)
    }

    @Test
    fun releaseFailureAfterDeclineIsCompensationFailure() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = true)
        pipeline.inventory.failRelease(true)

        val result = pipeline.useCase.execute(listOf(line("SKU-1", 1, 500)), "idem-5b")

        val failure = assertInstanceOf(PlaceOrderResult.Failure::class.java, result)
        assertInstanceOf(CompensationFailureError::class.java, failure.error)
    }

    @Test
    fun invalidLinesFailValidationWithoutTouchingPorts() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = false)

        val result = pipeline.useCase.execute(emptyList(), "idem-6")

        val failure = assertInstanceOf(PlaceOrderResult.Failure::class.java, result)
        assertInstanceOf(InvalidOrderError::class.java, failure.error)
        assertTrue(pipeline.payments.chargedOrders().isEmpty())
        assertTrue(pipeline.repository.saved().isEmpty())
        assertEquals(10, pipeline.inventory.snapshotStock()[Sku("SKU-1")])
    }

    @Test
    fun getReturnsNullForUnknownIdentifier() {
        val repository = InMemoryOrderRepository()
        assertNull(repository.get(OrderId("missing-order")))
    }

    @Test
    fun reserveAllIsIdempotentForTheSameKey() {
        val inventory = InMemoryInventoryGateway(mapOf(Sku("SKU-1") to 2))
        val lines = listOf(line("SKU-1", 1, 100))
        val first = inventory.reserveAll(OrderId("ord-1"), lines, "idem-x")
        val second = inventory.reserveAll(OrderId("ord-1"), lines, "idem-x")
        assertInstanceOf(ReservationOutcome.Reserved::class.java, first)
        assertInstanceOf(ReservationOutcome.Reserved::class.java, second)
        assertEquals(1, inventory.snapshotStock()[Sku("SKU-1")])
    }

    @Test
    fun releaseOfUnknownTokenSucceeds() {
        val inventory = InMemoryInventoryGateway(emptyMap())
        val outcome = inventory.release(ReservationToken(OrderId("ord-1"), "missing"))
        assertInstanceOf(ReleaseOutcome.Released::class.java, outcome)
    }

    @Test
    fun chargeIsIdempotentForTheSameKey() {
        val payments = FakePaymentProcessor(decline = false)
        val order = Order(OrderId("ord-1"), listOf(line("SKU-1", 1, 100)))
        val first = payments.charge(order, "idem-pay")
        val second = payments.charge(order, "idem-pay")
        assertInstanceOf(ChargeOutcome.Charged::class.java, first)
        assertInstanceOf(ChargeOutcome.Charged::class.java, second)
        assertEquals(1, payments.chargedOrders().size)
    }

    @Test
    fun saveThenGetReturnsDetachedPaidSnapshot() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = false)
        val result = pipeline.useCase.execute(listOf(line("SKU-1", 1, 100)), "idem-repo")
        val success = result as PlaceOrderResult.Success

        val loaded = pipeline.repository.get(success.order.id)!!
        loaded.ship()
        val stored = pipeline.repository.get(success.order.id)!!
        assertEquals(Order.Status.PAID, stored.status)
        assertEquals(1, stored.version)
    }

    @Test
    fun saveWithStaleVersionIsPersistenceConflict() {
        val repository = InMemoryOrderRepository()
        val order = Order(OrderId("ord-2"), listOf(line("SKU-1", 1, 100)))
        order.pay()
        assertInstanceOf(SaveOutcome.Saved::class.java, repository.save(order, 0))
        val retry = order.snapshot()
        retry.ship()
        assertInstanceOf(SaveOutcome.Conflict::class.java, repository.save(retry, 0))
        assertInstanceOf(SaveOutcome.Saved::class.java, repository.save(order, 1))
    }

    @Test
    fun idempotentReplayDoesNotDoubleCharge() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = false)
        val first = pipeline.useCase.execute(listOf(line("SKU-1", 2, 300)), "idem-7")
        val second = pipeline.useCase.execute(listOf(line("SKU-1", 2, 300)), "idem-7")

        assertInstanceOf(PlaceOrderResult.Success::class.java, first)
        assertInstanceOf(PlaceOrderResult.Success::class.java, second)
        assertEquals(Order.Status.PAID, (second as PlaceOrderResult.Success).order.status)
        assertEquals(1, pipeline.payments.chargedOrders().size)
        assertEquals(8, pipeline.inventory.snapshotStock()[Sku("SKU-1")])
    }

    @Test
    fun reusedKeyWithDifferentPayloadIsInvalidOrder() {
        val pipeline = Pipeline.create(mapOf("SKU-1" to 10), decline = false)
        pipeline.useCase.execute(listOf(line("SKU-1", 1, 100)), "idem-8")

        val result = pipeline.useCase.execute(listOf(line("SKU-1", 2, 100)), "idem-8")

        val failure = assertInstanceOf(PlaceOrderResult.Failure::class.java, result)
        val invalid = assertInstanceOf(InvalidOrderError::class.java, failure.error)
        assertTrue(invalid.reason.contains("idempotency"))
        assertEquals(1, pipeline.payments.chargedOrders().size)
    }

    @Test
    fun concurrentReservationsDoNotOversell() {
        val pipeline = Pipeline.create(mapOf("SKU-A" to 5), decline = false)
        val lines = listOf(line("SKU-A", 5, 100))
        val tasks =
            listOf<Callable<PlaceOrderResult>>(
                Callable { pipeline.useCase.execute(lines, "idem-9a") },
                Callable { pipeline.useCase.execute(lines, "idem-9b") }
            )

        val executor = Executors.newFixedThreadPool(2)
        try {
            val results = executor.invokeAll(tasks).map { join(it) }
            val successes = results.count { it is PlaceOrderResult.Success }
            val shortages =
                results.count { result ->
                    result is PlaceOrderResult.Failure && result.error is InsufficientStockError
                }
            assertEquals(1, successes)
            assertEquals(1, shortages)
        } finally {
            executor.shutdownNow()
        }
        assertEquals(0, pipeline.inventory.snapshotStock()[Sku("SKU-A")])
        assertEquals(1, pipeline.payments.chargedOrders().size)
    }

    private data class Pipeline(
        val useCase: PlaceOrderUseCase,
        val inventory: InMemoryInventoryGateway,
        val payments: FakePaymentProcessor,
        val repository: InMemoryOrderRepository
    ) {
        companion object {
            fun create(
                stock: Map<String, Int>,
                decline: Boolean
            ): Pipeline {
                val initialStock = stock.mapKeys { Sku(it.key) }
                val inventory = InMemoryInventoryGateway(initialStock)
                val payments = FakePaymentProcessor(decline)
                val repository = InMemoryOrderRepository()
                val seq = AtomicInteger()
                val ids = OrderIdGenerator { OrderId("ord-${seq.incrementAndGet()}") }
                return Pipeline(
                    PlaceOrderUseCase(inventory, payments, repository, ids),
                    inventory,
                    payments,
                    repository
                )
            }
        }
    }

    companion object {
        private const val USD = "USD"

        private fun line(
            sku: String,
            quantity: Int,
            minorUnits: Long
        ): OrderLine = OrderLine(Sku(sku), Quantity(quantity), Money(minorUnits, USD))

        private fun join(future: Future<PlaceOrderResult>): PlaceOrderResult =
            try {
                future.get()
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                throw AssertionError(error)
            } catch (error: java.util.concurrent.ExecutionException) {
                throw AssertionError(error)
            }
    }
}
