package com.warehouse.application;

import static org.assertj.core.api.Assertions.assertThat;

import com.warehouse.adapters.FakePaymentProcessor;
import com.warehouse.adapters.InMemoryInventoryGateway;
import com.warehouse.adapters.InMemoryOrderRepository;
import com.warehouse.application.InventoryGateway.ReleaseOutcome;
import com.warehouse.application.InventoryGateway.ReservationOutcome;
import com.warehouse.application.InventoryGateway.ReservationToken;
import com.warehouse.application.OrderRepository.SaveOutcome;
import com.warehouse.application.PaymentProcessor.ChargeOutcome;
import com.warehouse.domain.DomainError.CompensationFailureError;
import com.warehouse.domain.DomainError.InsufficientStockError;
import com.warehouse.domain.DomainError.InvalidOrderError;
import com.warehouse.domain.DomainError.PaymentDeclinedError;
import com.warehouse.domain.DomainError.PersistenceConflictError;
import com.warehouse.domain.Money;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderId;
import com.warehouse.domain.OrderLine;
import com.warehouse.domain.Quantity;
import com.warehouse.domain.Sku;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

/**
 * Integration tests: the full place-order pipeline over in-memory adapters, covering the happy path
 * plus each failure path (CONTRACTS.md §2).
 */
class PlaceOrderUseCaseTest {

  private static final String USD = "USD";

  private static OrderLine line(String sku, int quantity, long minorUnits) {
    return new OrderLine(new Sku(sku), new Quantity(quantity), new Money(minorUnits, USD));
  }

  /** The use case plus the doubles it was wired to, for interaction asserts. */
  private record Pipeline(
      PlaceOrderUseCase useCase,
      InMemoryInventoryGateway inventory,
      FakePaymentProcessor payments,
      InMemoryOrderRepository repository) {

    static Pipeline create(Map<String, Integer> stock, boolean decline) {
      Map<Sku, Integer> initialStock =
          stock.entrySet().stream()
              .collect(
                  java.util.stream.Collectors.toMap(e -> new Sku(e.getKey()), Map.Entry::getValue));
      var inventory = new InMemoryInventoryGateway(initialStock);
      var payments = new FakePaymentProcessor(decline);
      var repository = new InMemoryOrderRepository();
      var seq = new AtomicInteger();
      OrderIdGenerator ids = () -> new OrderId("ord-" + seq.incrementAndGet());
      return new Pipeline(
          new PlaceOrderUseCase(inventory, payments, repository, ids),
          inventory,
          payments,
          repository);
    }
  }

  @Test
  void happyPathReservesChargesPaysAndPersistsPaid() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 2, 500)), "idem-1");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Success.class,
            success -> {
              assertThat(success.order().state()).isEqualTo(Order.State.PAID);
              assertThat(success.order().id().value()).isEqualTo("ord-1");
              assertThat(success.order().total()).isEqualTo(new Money(1000, USD));
              assertThat(success.order().version()).isEqualTo(1);
              assertThat(pipeline.repository().get(success.order().id()))
                  .isPresent()
                  .hasValueSatisfying(
                      stored -> {
                        assertThat(stored.state()).isEqualTo(Order.State.PAID);
                        assertThat(stored).isNotSameAs(success.order());
                      });
            });
    assertThat(pipeline.payments().chargedOrders()).hasSize(1);
    assertThat(pipeline.repository().saved()).hasSize(1);
    assertThat(pipeline.inventory().snapshotStock().get(new Sku("SKU-1"))).isEqualTo(8);
  }

  @Test
  void insufficientStockFailsWithoutChargeOrPersist() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 1), false);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 5, 500)), "idem-2");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> {
              assertThat(failure.error()).isInstanceOf(InsufficientStockError.class);
              assertThat(((InsufficientStockError) failure.error()).available()).isEqualTo(1);
            });
    assertThat(pipeline.payments().chargedOrders()).isEmpty();
    assertThat(pipeline.repository().saved()).isEmpty();
    assertThat(pipeline.inventory().snapshotStock().get(new Sku("SKU-1"))).isEqualTo(1);
  }

  @Test
  void paymentDeclineReleasesReservationWithoutPersist() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), true);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 1, 500)), "idem-3");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> {
              assertThat(failure.error()).isInstanceOf(PaymentDeclinedError.class);
              assertThat(((PaymentDeclinedError) failure.error()).reason()).contains("declined");
            });
    assertThat(pipeline.payments().chargedOrders()).hasSize(1);
    assertThat(pipeline.repository().saved()).isEmpty();
    assertThat(pipeline.inventory().snapshotStock().get(new Sku("SKU-1"))).isEqualTo(10);
  }

  @Test
  void saveFailureRefundsAndReleases() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);
    pipeline.repository().failSave(true);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 1, 500)), "idem-4");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> assertThat(failure.error()).isInstanceOf(PersistenceConflictError.class));
    assertThat(pipeline.payments().refunded()).hasSize(1);
    assertThat(pipeline.inventory().snapshotStock().get(new Sku("SKU-1"))).isEqualTo(10);
    assertThat(pipeline.repository().saved()).isEmpty();
  }

  @Test
  void compensationFailureAfterSaveFailure() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);
    pipeline.repository().failSave(true);
    pipeline.payments().failRefund(true);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 1, 500)), "idem-5");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> assertThat(failure.error()).isInstanceOf(CompensationFailureError.class));
  }

  @Test
  void releaseFailureAfterSaveFailureIsCompensationFailure() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);
    pipeline.repository().failSave(true);
    pipeline.inventory().failRelease(true);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 1, 500)), "idem-5c");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> assertThat(failure.error()).isInstanceOf(CompensationFailureError.class));
    assertThat(pipeline.payments().refunded()).hasSize(1);
  }

  @Test
  void releaseFailureAfterDeclineIsCompensationFailure() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), true);
    pipeline.inventory().failRelease(true);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 1, 500)), "idem-5b");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> assertThat(failure.error()).isInstanceOf(CompensationFailureError.class));
  }

  @Test
  void invalidLinesFailValidationWithoutTouchingPorts() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);

    var result = pipeline.useCase().execute(List.of(), "idem-6");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> assertThat(failure.error()).isInstanceOf(InvalidOrderError.class));
    assertThat(pipeline.payments().chargedOrders()).isEmpty();
    assertThat(pipeline.repository().saved()).isEmpty();
    assertThat(pipeline.inventory().snapshotStock().get(new Sku("SKU-1"))).isEqualTo(10);
  }

  @Test
  void getReturnsEmptyForUnknownIdentifier() {
    var repository = new InMemoryOrderRepository();
    assertThat(repository.get(new OrderId("missing-order"))).isEmpty();
  }

  @Test
  void reserveAllIsIdempotentForTheSameKey() {
    var inventory = new InMemoryInventoryGateway(Map.of(new Sku("SKU-1"), 2));
    var lines = List.of(line("SKU-1", 1, 100));
    var first = inventory.reserveAll(new OrderId("ord-1"), lines, "idem-x");
    var second = inventory.reserveAll(new OrderId("ord-1"), lines, "idem-x");
    assertThat(first).isInstanceOf(ReservationOutcome.Reserved.class);
    assertThat(second).isInstanceOf(ReservationOutcome.Reserved.class);
    assertThat(inventory.snapshotStock().get(new Sku("SKU-1"))).isEqualTo(1);
  }

  @Test
  void releaseOfUnknownTokenSucceeds() {
    var inventory = new InMemoryInventoryGateway(Map.of());
    var outcome = inventory.release(new ReservationToken(new OrderId("ord-1"), "missing"));
    assertThat(outcome).isInstanceOf(ReleaseOutcome.Released.class);
  }

  @Test
  void chargeIsIdempotentForTheSameKey() {
    var payments = new FakePaymentProcessor(false);
    var order = new Order(new OrderId("ord-1"), List.of(line("SKU-1", 1, 100)));
    var first = payments.charge(order, "idem-pay");
    var second = payments.charge(order, "idem-pay");
    assertThat(first).isInstanceOf(ChargeOutcome.Charged.class);
    assertThat(second).isInstanceOf(ChargeOutcome.Charged.class);
    assertThat(payments.chargedOrders()).hasSize(1);
  }

  @Test
  void saveThenGetReturnsDetachedPaidSnapshot() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);
    var result = pipeline.useCase().execute(List.of(line("SKU-1", 1, 100)), "idem-repo");
    var success = (PlaceOrderResult.Success) result;

    var loaded = pipeline.repository().get(success.order().id()).orElseThrow();
    loaded.ship();
    var stored = pipeline.repository().get(success.order().id()).orElseThrow();
    assertThat(stored.state()).isEqualTo(Order.State.PAID);
    assertThat(stored.version()).isEqualTo(1);
  }

  @Test
  void saveWithStaleVersionIsPersistenceConflict() {
    var repository = new InMemoryOrderRepository();
    var order = new Order(new OrderId("ord-2"), List.of(line("SKU-1", 1, 100)));
    order.pay();
    assertThat(repository.save(order, 0)).isInstanceOf(OrderRepository.SaveOutcome.Saved.class);
    var retry = order.snapshot();
    retry.ship();
    assertThat(repository.save(retry, 0)).isInstanceOf(SaveOutcome.Conflict.class);
    assertThat(repository.save(order, 1)).isInstanceOf(SaveOutcome.Saved.class);
  }

  @Test
  void idempotentReplayDoesNotDoubleCharge() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);
    var first = pipeline.useCase().execute(List.of(line("SKU-1", 2, 300)), "idem-7");
    var second = pipeline.useCase().execute(List.of(line("SKU-1", 2, 300)), "idem-7");

    assertThat(first).isInstanceOf(PlaceOrderResult.Success.class);
    assertThat(second).isInstanceOf(PlaceOrderResult.Success.class);
    assertThat(((PlaceOrderResult.Success) second).order().state()).isEqualTo(Order.State.PAID);
    assertThat(pipeline.payments().chargedOrders()).hasSize(1);
    assertThat(pipeline.inventory().snapshotStock().get(new Sku("SKU-1"))).isEqualTo(8);
  }

  @Test
  void reusedKeyWithDifferentPayloadIsInvalidOrder() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);
    pipeline.useCase().execute(List.of(line("SKU-1", 1, 100)), "idem-8");

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 2, 100)), "idem-8");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> {
              assertThat(failure.error()).isInstanceOf(InvalidOrderError.class);
              assertThat(((InvalidOrderError) failure.error()).reason()).contains("idempotency");
            });
    assertThat(pipeline.payments().chargedOrders()).hasSize(1);
  }

  @Test
  void concurrentReservationsDoNotOversell() throws Exception {
    var pipeline = Pipeline.create(Map.of("SKU-A", 5), false);
    List<OrderLine> lines = List.of(line("SKU-A", 5, 100));
    List<Callable<PlaceOrderResult>> tasks =
        List.of(
            () -> pipeline.useCase().execute(lines, "idem-9a"),
            () -> pipeline.useCase().execute(lines, "idem-9b"));

    try (var executor = Executors.newFixedThreadPool(2)) {
      var futures = executor.invokeAll(tasks);
      var results = futures.stream().map(PlaceOrderUseCaseTest::join).toList();
      long successes = results.stream().filter(PlaceOrderResult.Success.class::isInstance).count();
      long shortages =
          results.stream()
              .filter(PlaceOrderResult.Failure.class::isInstance)
              .map(PlaceOrderResult.Failure.class::cast)
              .filter(failure -> failure.error() instanceof InsufficientStockError)
              .count();
      assertThat(successes).isEqualTo(1);
      assertThat(shortages).isEqualTo(1);
    }
    assertThat(pipeline.inventory().snapshotStock().get(new Sku("SKU-A"))).isZero();
    assertThat(pipeline.payments().chargedOrders()).hasSize(1);
  }

  private static PlaceOrderResult join(java.util.concurrent.Future<PlaceOrderResult> future) {
    try {
      return future.get();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new AssertionError(e);
    } catch (java.util.concurrent.ExecutionException e) {
      throw new AssertionError(e);
    }
  }
}
