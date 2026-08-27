import Dispatch

/// OrderRepository double keeping snapshots, never aliases.
public final class InMemoryOrderRepository: OrderRepository, @unchecked Sendable {
  private let queue = DispatchQueue(label: "warehouse.repository")
  private var orders: [OrderId: Order] = [:]
  private var byKey: [String: IdempotencyRecord] = [:]
  public private(set) var saved: [Order] = []
  public var failSave = false

  public init() {}

  public func save(_ order: Order, expectedVersion: Int) -> Result<Order, PersistenceConflict> {
    queue.sync {
      if failSave {
        return .failure(PersistenceConflict("forced save failure for \(order.id.value)"))
      }
      let currentVersion = orders[order.id]?.version ?? 0
      if currentVersion != expectedVersion {
        return .failure(
          PersistenceConflict(
            "version conflict for \(order.id.value): "
              + "expected \(expectedVersion), stored \(currentVersion)"
          )
        )
      }
      var snapshot = order.snapshot()
      snapshot.bumpVersion()
      orders[order.id] = snapshot
      saved.append(snapshot)
      return .success(snapshot)
    }
  }

  public func get(_ orderId: OrderId) -> Order? {
    queue.sync { orders[orderId] }
  }

  public func getByIdempotencyKey(_ key: String) -> IdempotencyRecord? {
    queue.sync { byKey[key] }
  }

  public func rememberIdempotency(key: String, fingerprint: String, order: Order) {
    queue.sync {
      byKey[key] = IdempotencyRecord(fingerprint: fingerprint, order: order.snapshot())
    }
  }
}
