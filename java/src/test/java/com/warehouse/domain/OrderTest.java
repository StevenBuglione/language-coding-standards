package com.warehouse.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.Currency;
import java.util.List;
import java.util.Locale;
import org.junit.jupiter.api.Test;

/** Order invariant and state-machine tests. */
class OrderTest {

  private static final Currency USD = Currency.getInstance(Locale.US);

  private static OrderLine line(String sku, int quantity, int minorUnits) {
    return new OrderLine(new Sku(sku), new Quantity(quantity), new Money(minorUnits, USD));
  }

  @Test
  void rejectsEmptyLineSets() {
    assertThatThrownBy(() -> new Order(List.of()))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("at least one line");
  }

  @Test
  void rejectsDuplicateSkusAcrossLines() {
    var lines = List.of(line("SKU-1", 1, 500), line("SKU-1", 2, 500));
    assertThatThrownBy(() -> new Order(lines))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("duplicate SKUs");
  }

  @Test
  void computesTotalAsSumOfLineTotals() {
    var order = new Order(List.of(line("SKU-1", 2, 500), line("SKU-2", 3, 250)));
    assertThat(order.total()).isEqualTo(new Money(1750, USD));
  }

  @Test
  void rejectsMixedCurrencyTotalsAsInvalid() {
    var mixed =
        List.of(
            new OrderLine(new Sku("SKU-1"), new Quantity(1), new Money(500, USD)),
            new OrderLine(
                new Sku("SKU-2"), new Quantity(1), new Money(500, Currency.getInstance("EUR"))));
    var order = new Order(mixed);
    assertThatThrownBy(order::total)
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("currency mismatch");
  }

  @Test
  void startsInNewStateWithFreshIdentifier() {
    var order = new Order(List.of(line("SKU-1", 1, 500)));
    assertThat(order.state()).isEqualTo(Order.State.NEW);
    assertThat(order.id().value()).isNotNull();
  }

  @Test
  void exposesAnImmutableLineList() {
    var order = new Order(List.of(line("SKU-1", 1, 500)));
    assertThatThrownBy(() -> order.lines().add(line("SKU-2", 1, 100)))
        .isInstanceOf(UnsupportedOperationException.class);
  }

  @Test
  void paysNewOrderThenShipsPaidOrder() {
    var order = new Order(List.of(line("SKU-1", 1, 500)));
    order.pay();
    assertThat(order.state()).isEqualTo(Order.State.PAID);
    order.ship();
    assertThat(order.state()).isEqualTo(Order.State.SHIPPED);
  }

  @Test
  void refusesToPayTwice() {
    var order = new Order(List.of(line("SKU-1", 1, 500)));
    order.pay();
    assertThatThrownBy(order::pay).isInstanceOf(IllegalStateException.class);
  }

  @Test
  void refusesToShipUnpaidOrders() {
    var order = new Order(List.of(line("SKU-1", 1, 500)));
    assertThatThrownBy(order::ship).isInstanceOf(IllegalStateException.class);
  }

  @Test
  void refusesAnyMutationAfterShipping() {
    var order = new Order(List.of(line("SKU-1", 1, 500)));
    order.pay();
    order.ship();
    assertThatThrownBy(order::pay).isInstanceOf(OrderAlreadyShipedException.class);
    assertThatThrownBy(order::ship).isInstanceOf(OrderAlreadyShipedException.class);
  }
}
