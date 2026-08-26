package com.warehouse.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.warehouse.domain.DomainError.InsufficientStockError;
import com.warehouse.domain.Money;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderLine;
import com.warehouse.domain.Quantity;
import com.warehouse.domain.Sku;
import java.util.Currency;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

/**
 * Orchestration-order tests with strict-stub mocks: fakes prove WHAT state results from a pipeline,
 * mocks prove IN WHICH ORDER the ports were touched. This is the one role where doubles beyond the
 * canonical fakes pay for themselves; STRICT_STUBS keeps every stub load-bearing (unused stubbing
 * fails the test).
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.STRICT_STUBS)
class PlaceOrderUseCaseOrchestrationTest {

  private static final Currency USD = Currency.getInstance("USD");

  @Mock private InventoryGateway inventory;

  @Mock private PaymentProcessor payments;

  @Mock private OrderRepository repository;

  private static OrderLine line(String sku, int quantity, int minorUnits) {
    return new OrderLine(new Sku(sku), new Quantity(quantity), new Money(minorUnits, USD));
  }

  @Test
  void reservesEveryLineBeforeChargingBeforePersisting() {
    when(inventory.reserve(any(Sku.class), any(Quantity.class)))
        .thenReturn(new InventoryGateway.ReservationOutcome.Reserved());
    when(payments.charge(any(Order.class)))
        .thenReturn(new PaymentProcessor.ChargeOutcome.Charged());
    when(repository.save(any(Order.class))).thenAnswer(invocation -> invocation.getArgument(0));

    var result =
        new PlaceOrderUseCase(inventory, payments, repository)
            .execute(List.of(line("SKU-1", 2, 500), line("SKU-2", 1, 250)));

    assertThat(result).isInstanceOf(PlaceOrderResult.Success.class);
    // Both lines reserve first, then one charge, then one persist: the
    // orchestration order fakes cannot pin down this precisely.
    InOrder pipeline = inOrder(inventory, payments, repository);
    pipeline.verify(inventory, times(2)).reserve(any(Sku.class), any(Quantity.class));
    pipeline.verify(payments).charge(any(Order.class));
    pipeline.verify(repository).save(any(Order.class));
  }

  @Test
  void firstShortageShortCircuitsBeforeChargeAndPersist() {
    when(inventory.reserve(any(Sku.class), any(Quantity.class)))
        .thenReturn(
            new InventoryGateway.ReservationOutcome.Shortage(
                new InsufficientStockError(new Sku("SKU-9"), new Quantity(5), 0)));

    var result =
        new PlaceOrderUseCase(inventory, payments, repository)
            .execute(List.of(line("SKU-9", 5, 500)));

    assertThat(result).isInstanceOf(PlaceOrderResult.Failure.class);
    verifyNoInteractions(payments, repository);
  }
}
