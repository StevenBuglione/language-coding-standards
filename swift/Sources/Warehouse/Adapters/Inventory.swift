import Dispatch

/// InventoryGateway double enforcing finite stock, for tests and demos.
public final class InMemoryInventoryGateway: InventoryGateway, @unchecked Sendable {
  private let queue = DispatchQueue(label: "warehouse.inventory")
  private var stock: [Sku: Int]
  private var reservations: [String: [(Sku, Int)]] = [:]
  public var failRelease = false

  public init(stock: [Sku: Int] = [:]) {
    self.stock = stock
  }

  public func snapshotStock() -> [Sku: Int] {
    queue.sync { stock }
  }

  public func reserveAll(
    orderId: OrderId,
    lines: [OrderLine],
    idempotencyKey: String
  ) -> Result<ReservationToken, InsufficientStock> {
    queue.sync {
      if reservations[idempotencyKey] != nil {
        return .success(ReservationToken(orderId: orderId, idempotencyKey: idempotencyKey))
      }
      var needed: [(Sku, Int)] = []
      for line in lines {
        let available = stock[line.sku] ?? 0
        if available < line.quantity.value {
          return .failure(
            InsufficientStock(
              sku: line.sku,
              requested: line.quantity,
              available: available
            )
          )
        }
        needed.append((line.sku, line.quantity.value))
      }
      for (sku, amount) in needed {
        stock[sku] = (stock[sku] ?? 0) - amount
      }
      reservations[idempotencyKey] = needed
      return .success(ReservationToken(orderId: orderId, idempotencyKey: idempotencyKey))
    }
  }

  public func release(token: ReservationToken) -> Result<Void, CompensationFailure> {
    queue.sync {
      if failRelease {
        return .failure(CompensationFailure(stage: "release", detail: "forced failure"))
      }
      guard let held = reservations.removeValue(forKey: token.idempotencyKey) else {
        return .success(())
      }
      for (sku, amount) in held {
        stock[sku] = (stock[sku] ?? 0) + amount
      }
      return .success(())
    }
  }
}
