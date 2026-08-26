package com.warehouse.domain;

import java.util.List;
import java.util.UUID;

/**
 * Order entity enforcing the four canonical invariants.
 *
 * <p>Invariants: at least one line; no duplicate SKUs across lines; the total always equals the sum
 * of line totals (computed, never stored stale); no mutation once shipped.
 *
 * <p>Transition methods signal misuse by throwing {@link IllegalStateException} or {@link
 * OrderAlreadyShipedException}. That is internal discipline only — the use-case boundary converts
 * outcomes into typed results, so neither ever escapes the application layer.
 *
 * <p>Final by design: a domain entity with a validating constructor must not be extendable
 * (finalizer attack surface, SpotBugs CT_CONSTRUCTOR_THROW).
 */
public final class Order {

  /** States of the canonical order life cycle. */
  public enum State {
    /** Freshly placed, not yet paid. */
    NEW,
    /** Payment collected, ready to ship. */
    PAID,
    /** Terminal state; further mutation is refused. */
    SHIPPED
  }

  private final OrderId id;
  private final List<OrderLine> lines;
  private State state;

  /**
   * Places a new order from validated lines, assigning a fresh identifier.
   *
   * @param lines at least one non-duplicate-SKU line, all in one currency
   * @throws InvalidOrderException when the list is empty or two lines share a SKU
   */
  public Order(List<OrderLine> lines) {
    List<OrderLine> safeLines = List.copyOf(lines);
    if (safeLines.isEmpty()) {
      throw new InvalidOrderException("an order requires at least one line");
    }
    long distinctSkus = safeLines.stream().map(line -> line.sku().code()).distinct().count();
    if (distinctSkus != safeLines.size()) {
      throw new InvalidOrderException("duplicate SKUs across order lines are not allowed");
    }
    this.id = new OrderId(UUID.randomUUID());
    this.lines = safeLines;
    this.state = State.NEW;
  }

  /**
   * Returns the immutable order identifier.
   *
   * @return the identifier assigned at placement time
   */
  public OrderId id() {
    return id;
  }

  /**
   * Returns the current state-machine state.
   *
   * @return the current life-cycle state
   */
  public State state() {
    return state;
  }

  /**
   * Returns an immutable view of the order lines.
   *
   * @return the lines exactly as validated at construction
   */
  public List<OrderLine> lines() {
    return lines;
  }

  /**
   * Returns the sum of all line totals.
   *
   * @return the grand total in the lines' shared currency
   * @throws InvalidOrderException when lines mix currencies: a currency mismatch is invalid, never
   *     coerced
   */
  public Money total() {
    Money total = lines.getFirst().lineTotal();
    for (OrderLine line : lines.subList(1, lines.size())) {
      total = total.add(line.lineTotal());
    }
    return total;
  }

  /**
   * Transitions NEW to PAID.
   *
   * @throws IllegalStateException when the order is not in NEW
   * @throws OrderAlreadyShipedException when the order already shipped
   */
  public void pay() {
    ensureNotShipped();
    if (state != State.NEW) {
      throw new IllegalStateException("only new orders can be paid, was " + state);
    }
    state = State.PAID;
  }

  /**
   * Transitions PAID to SHIPPED; only paid orders may ship.
   *
   * @throws IllegalStateException when the order is not in PAID
   * @throws OrderAlreadyShipedException when the order already shipped
   */
  public void ship() {
    ensureNotShipped();
    if (state != State.PAID) {
      throw new IllegalStateException("only paid orders can be shipped, was " + state);
    }
    state = State.SHIPPED;
  }

  private void ensureNotShipped() {
    if (state == State.SHIPPED) {
      throw new OrderAlreadyShipedException("order " + id.value() + " has already shipped");
    }
  }
}
