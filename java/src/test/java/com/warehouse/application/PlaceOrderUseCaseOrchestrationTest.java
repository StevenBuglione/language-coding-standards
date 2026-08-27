package com.warehouse.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.warehouse.application.InventoryGateway.ReleaseOutcome;
import com.warehouse.application.InventoryGateway.ReservationOutcome;
import com.warehouse.application.InventoryGateway.ReservationToken;
import com.warehouse.application.OrderRepository.SaveOutcome;
import com.warehouse.application.PaymentProcessor.ChargeOutcome;
import com.warehouse.application.PaymentProcessor.ChargeReceipt;
import com.warehouse.domain.DomainError.InsufficientStockError;
import com.warehouse.domain.DomainError.PaymentDeclinedError;
import com.warehouse.domain.Money;
import com.warehouse.domain.Order;
import com.warehouse.domain.OrderId;
import com.warehouse.domain.OrderLine;
import com.warehouse.domain.Quantity;
import com.warehouse.domain.Sku;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
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

  private static final String USD = "USD";
  private static final OrderId ORDER_ID = new OrderId("ord-1");

  @Mock private InventoryGateway inventory;

  @Mock private PaymentProcessor payments;

  @Mock private OrderRepository repository;

  @Mock private OrderIdGenerator ids;

  private static OrderLine line(String sku, int quantity, long minorUnits) {
    return new OrderLine(new Sku(sku), new Quantity(quantity), new Money(minorUnits, USD));
  }

  private void stubFreshCommand() {
    when(repository.getByIdempotencyKey(anyString())).thenReturn(Optional.empty());
    when(ids.next()).thenReturn(ORDER_ID);
  }

  @Test
  void reservesAllBeforeChargingBeforePersistingPaid() {
    stubFreshCommand();
    when(inventory.reserveAll(any(OrderId.class), anyList(), anyString()))
        .thenReturn(new ReservationOutcome.Reserved(new ReservationToken(ORDER_ID, "idem-1")));
    when(payments.charge(any(Order.class), anyString()))
        .thenReturn(new ChargeOutcome.Charged(new ChargeReceipt(ORDER_ID, "idem-1")));
    when(repository.save(any(Order.class), eq(0)))
        .thenAnswer(invocation -> new SaveOutcome.Saved(invocation.getArgument(0, Order.class)));

    var result =
        new PlaceOrderUseCase(inventory, payments, repository, ids)
            .execute(List.of(line("SKU-1", 2, 500), line("SKU-2", 1, 250)), "idem-1");

    assertThat(result).isInstanceOf(PlaceOrderResult.Success.class);
    ArgumentCaptor<Order> saved = ArgumentCaptor.forClass(Order.class);
    InOrder pipeline = inOrder(repository, ids, inventory, payments);
    pipeline.verify(repository).getByIdempotencyKey("idem-1");
    pipeline.verify(ids).next();
    pipeline.verify(inventory).reserveAll(eq(ORDER_ID), anyList(), eq("idem-1"));
    pipeline.verify(payments).charge(any(Order.class), eq("idem-1"));
    pipeline.verify(repository).save(saved.capture(), eq(0));
    assertThat(saved.getValue().state()).isEqualTo(Order.State.PAID);
    verify(repository).rememberIdempotency(eq("idem-1"), anyString(), any(Order.class));
  }

  @Test
  void firstShortageShortCircuitsBeforeChargeAndPersist() {
    stubFreshCommand();
    when(inventory.reserveAll(any(OrderId.class), anyList(), anyString()))
        .thenReturn(
            new ReservationOutcome.Shortage(
                new InsufficientStockError(new Sku("SKU-9"), new Quantity(5), 0)));

    var result =
        new PlaceOrderUseCase(inventory, payments, repository, ids)
            .execute(List.of(line("SKU-9", 5, 500)), "idem-2");

    assertThat(result).isInstanceOf(PlaceOrderResult.Failure.class);
    verifyNoInteractions(payments);
    verify(repository, never()).save(any(Order.class), anyInt());
  }

  @Test
  void declinedChargeReleasesReservationWithoutPersisting() {
    stubFreshCommand();
    var token = new ReservationToken(ORDER_ID, "idem-3");
    when(inventory.reserveAll(any(OrderId.class), anyList(), anyString()))
        .thenReturn(new ReservationOutcome.Reserved(token));
    when(payments.charge(any(Order.class), anyString()))
        .thenReturn(new ChargeOutcome.Declined(new PaymentDeclinedError("declined")));
    when(inventory.release(token)).thenReturn(new ReleaseOutcome.Released());

    var result =
        new PlaceOrderUseCase(inventory, payments, repository, ids)
            .execute(List.of(line("SKU-1", 1, 500)), "idem-3");

    assertThat(result)
        .isInstanceOfSatisfying(
            PlaceOrderResult.Failure.class,
            failure -> assertThat(failure.error()).isInstanceOf(PaymentDeclinedError.class));
    InOrder pipeline = inOrder(inventory, payments, repository);
    pipeline.verify(inventory).reserveAll(any(OrderId.class), anyList(), eq("idem-3"));
    pipeline.verify(payments).charge(any(Order.class), eq("idem-3"));
    pipeline.verify(inventory).release(token);
    verify(repository, never()).save(any(Order.class), anyInt());
  }
}
