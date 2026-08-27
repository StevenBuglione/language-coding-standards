/// Proof that stock for an order was reserved atomically.
public struct ReservationToken: Equatable, Sendable {
  public let orderId: OrderId
  public let idempotencyKey: String

  public init(orderId: OrderId, idempotencyKey: String) {
    self.orderId = orderId
    self.idempotencyKey = idempotencyKey
  }
}

/// Proof that payment was collected for an idempotency key.
public struct ChargeReceipt: Equatable, Sendable {
  public let orderId: OrderId
  public let idempotencyKey: String

  public init(orderId: OrderId, idempotencyKey: String) {
    self.orderId = orderId
    self.idempotencyKey = idempotencyKey
  }
}

/// Fingerprint and snapshot for a previous successful command.
public struct IdempotencyRecord: Equatable, Sendable {
  public let fingerprint: String
  public let order: Order

  public init(fingerprint: String, order: Order) {
    self.fingerprint = fingerprint
    self.order = order
  }
}

/// Outbound port that mints deterministic-in-tests order identifiers.
public protocol OrderIdGenerator: Sendable {
  func next() -> OrderId
}

/// Outbound port for atomic stock reservation.
public protocol InventoryGateway: Sendable {
  func reserveAll(
    orderId: OrderId,
    lines: [OrderLine],
    idempotencyKey: String
  ) -> Result<ReservationToken, InsufficientStock>

  func release(token: ReservationToken) -> Result<Void, CompensationFailure>
}

/// Outbound port for idempotent payment collection.
public protocol PaymentProcessor: Sendable {
  func charge(_ order: Order, idempotencyKey: String) -> Result<ChargeReceipt, PaymentDeclined>
  func refund(_ receipt: ChargeReceipt) -> Result<Void, CompensationFailure>
}

/// Outbound port that persists and retrieves immutable snapshots.
public protocol OrderRepository: Sendable {
  func save(_ order: Order, expectedVersion: Int) -> Result<Order, PersistenceConflict>
  func get(_ orderId: OrderId) -> Order?
  func getByIdempotencyKey(_ key: String) -> IdempotencyRecord?
  func rememberIdempotency(key: String, fingerprint: String, order: Order)
}

/// Current instant. Production code must inject this instead of reading the clock.
public protocol Clock: Sendable {
  /// Unix epoch milliseconds. The domain never reads wall-clock time itself.
  func now() -> Int64
}
