import Dispatch

/// Test double that always returns the same injected identifier.
public struct FixedOrderIdGenerator: OrderIdGenerator {
  private let orderId: OrderId

  public init(_ orderId: OrderId) {
    self.orderId = orderId
  }

  public func next() -> OrderId {
    orderId
  }
}

/// Test double that issues `ord-1`, `ord-2`, ...
public final class SequenceOrderIdGenerator: OrderIdGenerator, @unchecked Sendable {
  private let queue = DispatchQueue(label: "warehouse.ids")
  private var n = 0
  private let prefix: String

  public init(prefix: String = "ord") {
    self.prefix = prefix
  }

  public func next() -> OrderId {
    queue.sync {
      n += 1
      return OrderId(sequence: n, prefix: prefix)
    }
  }
}
