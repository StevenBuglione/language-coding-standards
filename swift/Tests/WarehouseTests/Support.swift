import Testing
import Warehouse

func expectInvalidOrder(_ work: () throws -> Void, contains needle: String) {
  do {
    try work()
    Issue.record("expected InvalidOrder")
  } catch let error as InvalidOrder {
    #expect(error.reason.contains(needle))
  } catch {
    Issue.record("unexpected error \(error)")
  }
}

func usd(_ minorUnits: Int) throws -> Money {
  try Money(minorUnits: minorUnits, currency: "USD")
}

func line(
  _ code: String = "SKU-1",
  quantity: Int = 2,
  minorUnits: Int = 500,
  currency: String = "USD"
) throws -> OrderLine {
  OrderLine(
    sku: try Sku(code),
    quantity: try Quantity(quantity),
    unitPrice: try Money(minorUnits: minorUnits, currency: currency)
  )
}

func pipeline(
  stock: [String: Int],
  decline: Bool = false,
  orderId: String = "ord-1"
) throws -> (
  PlaceOrderUseCase,
  FakePaymentProcessor,
  InMemoryOrderRepository,
  InMemoryInventoryGateway
) {
  var mapped: [Sku: Int] = [:]
  for (code, units) in stock {
    mapped[try Sku(code)] = units
  }
  let inventory = InMemoryInventoryGateway(stock: mapped)
  let payments = FakePaymentProcessor(decline: decline)
  let repository = InMemoryOrderRepository()
  let useCase = PlaceOrderUseCase(
    inventory: inventory,
    payments: payments,
    repository: repository,
    ids: FixedOrderIdGenerator(try OrderId(orderId))
  )
  return (useCase, payments, repository, inventory)
}
