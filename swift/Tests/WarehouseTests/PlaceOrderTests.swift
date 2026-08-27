import Testing
import Warehouse

@Suite("PlaceOrder")
struct PlaceOrderTests {
  @Test func happyPathPersistsPaid() throws {
    let (useCase, payments, repository, inventory) = try pipeline(stock: ["SKU-1": 10])
    let result = useCase.execute(
      lines: [try line("SKU-1", quantity: 2, minorUnits: 500)],
      idempotencyKey: "idem-1"
    )
    guard case .success(let order) = result else {
      Issue.record("expected success, got \(result)")
      return
    }
    #expect(order.status == .paid)
    #expect(order.id.value == "ord-1")
    let total = try order.total()
    let expected = try usd(1000)
    #expect(total == expected)
    #expect(payments.chargedOrders.count == 1)
    let stored = repository.get(order.id)
    #expect(stored?.status == .paid)
    #expect(inventory.snapshotStock()[try Sku("SKU-1")] == 8)
  }

  @Test func insufficientStockFailsWithoutChargeOrPersist() throws {
    let (useCase, payments, repository, inventory) = try pipeline(stock: ["SKU-1": 1])
    let result = useCase.execute(
      lines: [try line("SKU-1", quantity: 5, minorUnits: 500)],
      idempotencyKey: "idem-2"
    )
    guard case .failure(.insufficientStock(let error)) = result else {
      Issue.record("expected insufficient stock, got \(result)")
      return
    }
    #expect(error.available == 1)
    #expect(payments.chargedOrders.isEmpty)
    #expect(repository.saved.isEmpty)
    #expect(inventory.snapshotStock()[try Sku("SKU-1")] == 1)
  }

  @Test func paymentDeclineReleasesReservation() throws {
    let (useCase, payments, repository, inventory) = try pipeline(
      stock: ["SKU-1": 10],
      decline: true
    )
    let result = useCase.execute(
      lines: [try line("SKU-1", quantity: 1, minorUnits: 500)],
      idempotencyKey: "idem-3"
    )
    guard case .failure(.paymentDeclined(_)) = result else {
      Issue.record("expected payment declined, got \(result)")
      return
    }
    #expect(payments.chargedOrders.count == 1)
    #expect(repository.saved.isEmpty)
    #expect(inventory.snapshotStock()[try Sku("SKU-1")] == 10)
  }

  @Test func saveFailureRefundsAndReleases() throws {
    let (useCase, payments, repository, inventory) = try pipeline(stock: ["SKU-1": 10])
    repository.failSave = true
    let result = useCase.execute(
      lines: [try line("SKU-1", quantity: 1, minorUnits: 500)],
      idempotencyKey: "idem-4"
    )
    guard case .failure(.persistenceConflict(_)) = result else {
      Issue.record("expected persistence conflict, got \(result)")
      return
    }
    #expect(payments.refunded.count == 1)
    #expect(inventory.snapshotStock()[try Sku("SKU-1")] == 10)
  }

  @Test func compensationFailureAfterSaveFailure() throws {
    let (useCase, payments, repository, _) = try pipeline(stock: ["SKU-1": 10])
    repository.failSave = true
    payments.failRefund = true
    let result = useCase.execute(
      lines: [try line("SKU-1", quantity: 1, minorUnits: 500)],
      idempotencyKey: "idem-5"
    )
    guard case .failure(.compensationFailure(_)) = result else {
      Issue.record("expected compensation failure, got \(result)")
      return
    }
  }

  @Test func invalidLinesFailValidation() throws {
    let (useCase, _, _, _) = try pipeline(stock: [:])
    let result = useCase.execute(lines: [], idempotencyKey: "idem-6")
    guard case .failure(.invalidOrder(_)) = result else {
      Issue.record("expected invalid order, got \(result)")
      return
    }
  }

  @Test func getReturnsNilForUnknownId() throws {
    let (_, _, repository, _) = try pipeline(stock: ["SKU-1": 10])
    #expect(repository.get(try OrderId("missing-order")) == nil)
  }

  @Test func idempotentReplayDoesNotDoubleCharge() throws {
    var mapped: [Sku: Int] = [:]
    mapped[try Sku("SKU-1")] = 10
    let inventory = InMemoryInventoryGateway(stock: mapped)
    let payments = FakePaymentProcessor()
    let repository = InMemoryOrderRepository()
    let useCase = PlaceOrderUseCase(
      inventory: inventory,
      payments: payments,
      repository: repository,
      ids: SequenceOrderIdGenerator()
    )
    let lines = [try line("SKU-1", quantity: 2, minorUnits: 300)]
    let first = useCase.execute(lines: lines, idempotencyKey: "idem-7")
    let second = useCase.execute(lines: lines, idempotencyKey: "idem-7")
    guard case .success(_) = first, case .success(_) = second else {
      Issue.record("expected two successes, got \(first) \(second)")
      return
    }
    #expect(payments.chargedOrders.count == 1)
  }

  @Test func reusingKeyWithDifferentPayloadIsInvalid() throws {
    let (useCase, payments, _, _) = try pipeline(stock: ["SKU-1": 10, "SKU-2": 10])
    let first = useCase.execute(
      lines: [try line("SKU-1", quantity: 1, minorUnits: 100)],
      idempotencyKey: "idem-8"
    )
    let second = useCase.execute(
      lines: [try line("SKU-2", quantity: 1, minorUnits: 100)],
      idempotencyKey: "idem-8"
    )
    guard case .success(_) = first else {
      Issue.record("expected first success, got \(first)")
      return
    }
    guard case .failure(.invalidOrder(let error)) = second else {
      Issue.record("expected invalid order on reuse, got \(second)")
      return
    }
    #expect(error.reason.contains("idempotency"))
    #expect(payments.chargedOrders.count == 1)
  }

  @Test func clockPortIsInjectable() {
    let clock = FixedClock(1_700_000_000_000)
    #expect(clock.now() == 1_700_000_000_000)
  }
}
