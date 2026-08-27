package com.warehouse.domain;

import java.util.List;

/**
 * Order entity enforcing the canonical invariants.
 *
 * <p>Invariants: injected id; at least one line; no duplicate normalized SKUs; single currency at
 * construction; the total always equals the checked sum of line totals; only {@code NEW → PAID →
 * SHIPPED} is legal.
 *
 * <p>Transition methods signal misuse by throwing {@link InvalidOrderException} or {@link
 * OrderAlreadyShippedException}. That is internal discipline only — the use-case boundary converts
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
  private int version;

  /**
   * Places a new order from validated lines and an injected identifier.
   *
   * @param id identifier minted by the application, never by this constructor
   * @param lines at least one non-duplicate-SKU line, all in one currency
   * @throws InvalidOrderException when the list is empty, two lines share a SKU, or currencies mix
   */
  public Order(OrderId id, List<OrderLine> lines) {
    List<OrderLine> safeLines = List.copyOf(lines);
    if (safeLines.isEmpty()) {
      throw new InvalidOrderException("an order requires at least one line");
    }
    long distinctSkus = safeLines.stream().map(line -> line.sku().code()).distinct().count();
    if (distinctSkus != safeLines.size()) {
      throw new InvalidOrderException("duplicate SKUs across order lines are not allowed");
    }
    String currency = safeLines.getFirst().unitPrice().currency();
    for (OrderLine line : safeLines) {
      if (!currency.equals(line.unitPrice().currency())) {
        throw new InvalidOrderException("mixed currencies are not allowed");
      }
    }
    this.id = id;
    this.lines = safeLines;
    this.state = State.NEW;
    this.version = 0;
  }

  private Order(OrderId id, List<OrderLine> lines, State state, int version) {
    this.id = id;
    this.lines = lines;
    this.state = state;
    this.version = version;
  }

  /**
   * Returns the immutable order identifier.
   *
   * @return the identifier injected at construction
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
   * Returns the optimistic concurrency version.
   *
   * @return {@code 0} for a newly constructed aggregate; persistence increments on a successful
   *     save
   */
  public int version() {
    return version;
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
   * Returns the sum of all line totals in the order's single currency.
   *
   * @return the grand total computed with checked arithmetic
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
   * @throws InvalidOrderException when the order is already paid
   * @throws OrderAlreadyShippedException when the order already shipped
   */
  public void pay() {
    ensureNotShipped();
    if (state != State.NEW) {
      throw new InvalidOrderException("order has already been paid");
    }
    state = State.PAID;
  }

  /**
   * Transitions PAID to SHIPPED; only paid orders may ship.
   *
   * @throws InvalidOrderException when the order is not in PAID
   * @throws OrderAlreadyShippedException when the order already shipped
   */
  public void ship() {
    ensureNotShipped();
    if (state != State.PAID) {
      throw new InvalidOrderException("only paid orders can be shipped");
    }
    state = State.SHIPPED;
  }

  /**
   * Increments the optimistic version after a successful save.
   *
   * <p>Called by the repository on a snapshot, never as a domain state transition.
   */
  public void bumpVersion() {
    version++;
  }

  /**
   * Returns a detached copy so repositories cannot alias stored state.
   *
   * @return a new {@code Order} with the same id, lines, state, and version
   */
  public Order snapshot() {
    return new Order(id, lines, state, version);
  }

  private void ensureNotShipped() {
    if (state == State.SHIPPED) {
      throw new OrderAlreadyShippedException("order " + id.value() + " has already shipped");
    }
  }
}
