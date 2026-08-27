/// Immutable unique identifier of an order, injected by the application.
///
/// The domain never reads randomness, a process-global counter, or the clock.
public struct OrderId: Equatable, Hashable, Sendable, CustomStringConvertible {
  public let value: String

  public init(_ value: String) throws {
    if value.isEmpty || value.allSatisfy(\.isWhitespace) {
      throw InvalidOrder("order id must be non-empty")
    }
    self.value = value
  }

  /// Sequence tokens of the form `prefix-n` are never empty.
  public init(sequence n: Int, prefix: String = "ord") {
    self.value = "\(prefix)-\(n)"
  }

  public var description: String { value }
}

/// States of the canonical order life cycle.
public enum OrderStatus: String, Equatable, Sendable {
  case new = "NEW"
  case paid = "PAID"
  case shipped = "SHIPPED"
}

/// One SKU/quantity/unit-price row of an order.
public struct OrderLine: Equatable, Hashable, Sendable {
  public let sku: Sku
  public let quantity: Quantity
  public let unitPrice: Money

  public init(sku: Sku, quantity: Quantity, unitPrice: Money) {
    self.sku = sku
    self.quantity = quantity
    self.unitPrice = unitPrice
  }

  /// Return the unit price scaled by the ordered quantity.
  public func lineTotal() throws -> Money {
    try unitPrice.times(quantity.value)
  }
}

/// Order aggregate: injected id, immutable lines, `NEW -> PAID -> SHIPPED`.
///
/// Invariants: at least one line; no duplicate normalized SKUs; single
/// currency at construction; total is computed with checked arithmetic;
/// optimistic version starts at 0.
public struct Order: Equatable, Sendable {
  public let id: OrderId
  public let lines: [OrderLine]
  public private(set) var status: OrderStatus
  public private(set) var version: Int

  public init(id: OrderId, lines: [OrderLine]) throws {
    if lines.isEmpty {
      throw InvalidOrder("an order requires at least one line")
    }
    var seen: Set<String> = []
    for line in lines {
      if !seen.insert(line.sku.code).inserted {
        throw InvalidOrder("duplicate SKUs across order lines are not allowed")
      }
    }
    let currency = lines[0].unitPrice.currency
    if lines.contains(where: { $0.unitPrice.currency != currency }) {
      throw InvalidOrder("mixed currencies are not allowed")
    }
    self.id = id
    self.lines = lines
    self.status = .new
    self.version = 0
  }

  /// Return the sum of all line totals in a single currency.
  public func total() throws -> Money {
    var total = try lines[0].lineTotal()
    for line in lines.dropFirst() {
      total = try total.add(line.lineTotal())
    }
    return total
  }

  /// Transition NEW to PAID; refuse paid or already-shipped orders.
  public mutating func pay() throws {
    try ensureNotShipped()
    if status == .paid {
      throw InvalidOrder("order has already been paid")
    }
    status = .paid
  }

  /// Transition PAID to SHIPPED; only paid orders may ship.
  public mutating func ship() throws {
    try ensureNotShipped()
    if status != .paid {
      throw InvalidOrder("only paid orders can be shipped")
    }
    status = .shipped
  }

  /// Increment the optimistic version after a successful save.
  public mutating func bumpVersion() {
    version += 1
  }

  /// Return a detached copy so repositories cannot alias stored state.
  public func snapshot() -> Order {
    self
  }

  private func ensureNotShipped() throws {
    if status == .shipped {
      throw OrderAlreadyShipped(id)
    }
  }
}
