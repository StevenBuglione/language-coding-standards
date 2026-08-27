package com.warehouse.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.util.List;
import org.junit.jupiter.api.Test;

/** Order invariant and state-machine tests. */
class OrderTest {

  private static final String USD = "USD";

  private static OrderId id() {
    return new OrderId("ord-1");
  }

  private static OrderLine line(String sku, int quantity, long minorUnits) {
    return new OrderLine(new Sku(sku), new Quantity(quantity), new Money(minorUnits, USD));
  }

  private static Order order(OrderLine... lines) {
    return new Order(id(), List.of(lines));
  }

  @Test
  void rejectsEmptyLineSets() {
    assertThatThrownBy(() -> new Order(id(), List.of()))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("at least one line");
  }

  @Test
  void rejectsBlankOrderId() {
    assertThatThrownBy(() -> new OrderId(" "))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("order id");
  }

  @Test
  void rejectsDuplicateSkusAcrossLines() {
    var lines = List.of(line("SKU-1", 1, 500), line("SKU-1", 2, 500));
    assertThatThrownBy(() -> new Order(id(), lines))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("duplicate SKUs");
  }

  @Test
  void rejectsDuplicateSkusAfterNormalization() {
    var lines = List.of(line("SKU-1", 1, 500), line(" SKU-1 ", 2, 500));
    assertThatThrownBy(() -> new Order(id(), lines))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("duplicate SKUs");
  }

  @Test
  void computesTotalAsSumOfLineTotals() {
    var placed = order(line("SKU-1", 2, 500), line("SKU-2", 3, 250));
    assertThat(placed.total()).isEqualTo(new Money(1750, USD));
  }

  @Test
  void rejectsMixedCurrenciesAtConstruction() {
    var mixed =
        List.of(
            new OrderLine(new Sku("SKU-1"), new Quantity(1), new Money(500, USD)),
            new OrderLine(new Sku("SKU-2"), new Quantity(1), new Money(500, "EUR")));
    assertThatThrownBy(() -> new Order(id(), mixed))
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("mixed currencies");
  }

  @Test
  void usesInjectedIdAndStartsNewAtVersionZero() {
    var placed = new Order(new OrderId("ord-fixed-9"), List.of(line("SKU-1", 1, 500)));
    assertThat(placed.state()).isEqualTo(Order.State.NEW);
    assertThat(placed.id().value()).isEqualTo("ord-fixed-9");
    assertThat(placed.version()).isZero();
  }

  @Test
  void exposesAnImmutableLineList() {
    var placed = order(line("SKU-1", 1, 500));
    assertThatThrownBy(() -> placed.lines().add(line("SKU-2", 1, 100)))
        .isInstanceOf(UnsupportedOperationException.class);
  }

  @Test
  void snapshotIsDetachedFromTheOriginal() {
    var original = order(line("SKU-1", 1, 500));
    var copy = original.snapshot();
    copy.pay();
    copy.bumpVersion();
    assertThat(original.state()).isEqualTo(Order.State.NEW);
    assertThat(original.version()).isZero();
    assertThat(copy.state()).isEqualTo(Order.State.PAID);
    assertThat(copy.version()).isEqualTo(1);
  }

  @Test
  void paysNewOrderThenShipsPaidOrder() {
    var placed = order(line("SKU-1", 1, 500));
    placed.pay();
    assertThat(placed.state()).isEqualTo(Order.State.PAID);
    placed.ship();
    assertThat(placed.state()).isEqualTo(Order.State.SHIPPED);
  }

  @Test
  void refusesToPayTwice() {
    var placed = order(line("SKU-1", 1, 500));
    placed.pay();
    assertThatThrownBy(placed::pay)
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("already been paid");
  }

  @Test
  void refusesToShipUnpaidOrders() {
    var placed = order(line("SKU-1", 1, 500));
    assertThatThrownBy(placed::ship)
        .isInstanceOf(InvalidOrderException.class)
        .hasMessageContaining("paid");
  }

  @Test
  void refusesAnyMutationAfterShipping() {
    var placed = order(line("SKU-1", 1, 500));
    placed.pay();
    placed.ship();
    assertThatThrownBy(placed::pay).isInstanceOf(OrderAlreadyShippedException.class);
    assertThatThrownBy(placed::ship).isInstanceOf(OrderAlreadyShippedException.class);
  }
}
