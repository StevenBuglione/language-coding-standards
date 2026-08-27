/// Typed domain failures that cross the use-case boundary as values.
///
/// Programmer bugs and invariant-corrupting states must not be mislabeled as
/// business failures.

/// An order or value violates a structural domain invariant.
public struct InvalidOrder: Error, Equatable, Sendable, CustomStringConvertible {
  public let reason: String

  public init(_ reason: String) {
    self.reason = reason
  }

  public var description: String { reason }
}

/// The inventory cannot cover the requested quantity for a SKU.
public struct InsufficientStock: Error, Equatable, Sendable, CustomStringConvertible {
  public let sku: Sku
  public let requested: Quantity
  public let available: Int

  public init(sku: Sku, requested: Quantity, available: Int) {
    self.sku = sku
    self.requested = requested
    self.available = available
  }

  public var description: String {
    "insufficient stock for \(sku.code): requested \(requested.value), available \(available)"
  }
}

/// The payment processor refused to charge the order.
public struct PaymentDeclined: Error, Equatable, Sendable, CustomStringConvertible {
  public let reason: String

  public init(_ reason: String) {
    self.reason = reason
  }

  public var description: String { reason }
}

/// An optimistic save lost a compare-and-set race.
public struct PersistenceConflict: Error, Equatable, Sendable, CustomStringConvertible {
  public let reason: String

  public init(_ reason: String) {
    self.reason = reason
  }

  public var description: String { reason }
}

/// An adapter failed with a stage and retryability.
public struct InfrastructureFailure: Error, Equatable, Sendable, CustomStringConvertible {
  public let stage: String
  public let retryable: Bool
  public let detail: String

  public init(stage: String, retryable: Bool, detail: String) {
    self.stage = stage
    self.retryable = retryable
    self.detail = detail
  }

  public var description: String { "\(stage): \(detail)" }
}

/// Refund or reservation release failed after a partial success.
public struct CompensationFailure: Error, Equatable, Sendable, CustomStringConvertible {
  public let stage: String
  public let detail: String

  public init(stage: String, detail: String) {
    self.stage = stage
    self.detail = detail
  }

  public var description: String { "compensation failed at \(stage): \(detail)" }
}

/// A shipped order can no longer be mutated.
public struct OrderAlreadyShipped: Error, Equatable, Sendable, CustomStringConvertible {
  public let orderId: OrderId

  public init(_ orderId: OrderId) {
    self.orderId = orderId
  }

  public var description: String { "order \(orderId.value) has already shipped" }
}
