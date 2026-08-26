package com.warehouse.application;

import static org.assertj.core.api.Assertions.assertThat;

import com.warehouse.adapters.FakePaymentProcessor;
import com.warehouse.adapters.InMemoryInventoryGateway;
import com.warehouse.adapters.InMemoryOrderRepository;
import com.warehouse.domain.DomainError.InsufficientStockError;
import com.warehouse.domain.DomainError.InvalidOrderError;
import com.warehouse.domain.Money;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderId;
import com.warehouse.domain.OrderLine;
import com.warehouse.domain.Quantity;
import com.warehouse.domain.Sku;
import java.util.Currency;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * Integration tests: the full place-order pipeline over in-memory adapters, covering the happy path
 * plus each failure path (CONTRACTS.md §2).
 */
class PlaceOrderUseCaseTest {

  private static final Currency USD = Currency.getInstance("USD");

  private static OrderLine line(String sku, int quantity, int minorUnits) {
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
      return new Pipeline(
          new PlaceOrderUseCase(inventory, payments, repository), inventory, payments, repository);
    }
  }

  @Test
  void happyPathReservesChargesAndPersists() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), false);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 2, 500)));

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Success.class,
            success -> {
              assertThat(success.order().state()).isEqualTo(Order.State.NEW);
              assertThat(success.order().total()).isEqualTo(new Money(1000, USD));
              assertThat(pipeline.repository().get(success.order().id())).contains(success.order());
            });
    assertThat(pipeline.payments().chargedOrders()).hasSize(1);
    assertThat(pipeline.repository().saved()).hasSize(1);
  }

  @Test
  void insufficientStockFailsWithoutChargeOrPersist() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 1), false);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 5, 500)));

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> {
              assertThat(failure.error()).isInstanceOf(InsufficientStockError.class);
              assertThat(((InsufficientStockError) failure.error()).available()).isEqualTo(1);
            });
    // The shortage short-circuits before charging or persisting anything.
    assertThat(pipeline.payments().chargedOrders()).isEmpty();
    assertThat(pipeline.repository().saved()).isEmpty();
  }

  @Test
  void paymentDeclineFailsWithoutPersist() {
    var pipeline = Pipeline.create(Map.of("SKU-1", 10), true);

    var result = pipeline.useCase().execute(List.of(line("SKU-1", 1, 500)));

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> {
              assertThat(failure.error()).isInstanceOf(InvalidOrderError.class);
              assertThat(((InvalidOrderError) failure.error()).reason()).contains("declined");
            });
    // Collection may have been attempted, but nothing is ever persisted.
    assertThat(pipeline.payments().chargedOrders()).hasSize(1);
    assertThat(pipeline.repository().saved()).isEmpty();
  }

  @Test
  void invalidLinesFailValidationWithoutTouchingPorts() {
    var pipeline = Pipeline.create(Map.of(), false);

    var result = pipeline.useCase().execute(List.of());

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> assertThat(failure.error()).isInstanceOf(InvalidOrderError.class));
    assertThat(pipeline.payments().chargedOrders()).isEmpty();
    assertThat(pipeline.repository().saved()).isEmpty();
  }

  @Test
  void getReturnsEmptyForUnknownIdentifier() {
    var repository = new InMemoryOrderRepository();
    assertThat(repository.get(new OrderId(UUID.randomUUID()))).isEmpty();
  }
}
