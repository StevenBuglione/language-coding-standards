import Testing
import Warehouse

@Suite("Order")
struct OrderTests {
  @Test func rejectsEmptyLineSet() {
    expectInvalidOrder(
      { _ = try Order(id: OrderId("ord-1"), lines: []) },
      contains: "at least one line"
    )
  }

  @Test func rejectsDuplicateSkus() {
    expectInvalidOrder(
      {
        _ = try Order(
          id: OrderId("ord-1"),
          lines: [line("SKU-1"), line("SKU-1")]
        )
      },
      contains: "duplicate"
    )
  }

  @Test func rejectsDuplicateSkusAfterNormalization() {
    expectInvalidOrder(
      {
        _ = try Order(
          id: OrderId("ord-1"),
          lines: [line("SKU-1"), line(" SKU-1 ")]
        )
      },
      contains: "duplicate"
    )
  }

  @Test func totalEqualsSumOfLineTotals() throws {
    let order = try Order(
      id: OrderId("ord-1"),
      lines: [
        line("SKU-1", quantity: 2, minorUnits: 500),
        line("SKU-2", quantity: 1, minorUnits: 1000),
      ]
    )
    #expect(try order.total() == try usd(2000))
  }

  @Test func rejectsMixedCurrenciesAtConstruction() {
    expectInvalidOrder(
      {
        _ = try Order(
          id: OrderId("ord-1"),
          lines: [
            line("SKU-1"),
            line("SKU-2", quantity: 1, minorUnits: 100, currency: "EUR"),
          ]
        )
      },
      contains: "mixed currencies"
    )
  }

  @Test func usesInjectedId() throws {
    let order = try Order(id: OrderId("ord-fixed-9"), lines: [line()])
    #expect(order.id.value == "ord-fixed-9")
    #expect(order.status == .new)
    #expect(order.version == 0)
  }

  @Test func rejectsEmptyOrderId() {
    expectInvalidOrder({ _ = try OrderId("   ") }, contains: "non-empty")
  }

  @Test func payTransitionsNewToPaid() throws {
    var order = try Order(id: OrderId("ord-1"), lines: [line()])
    try order.pay()
    #expect(order.status == .paid)
  }

  @Test func doublePayIsInvalid() throws {
    var order = try Order(id: OrderId("ord-1"), lines: [line()])
    try order.pay()
    expectInvalidOrder({ try order.pay() }, contains: "already been paid")
  }

  @Test func shipRequiresPaidState() throws {
    var order = try Order(id: OrderId("ord-1"), lines: [line()])
    expectInvalidOrder({ try order.ship() }, contains: "paid")
  }

  @Test func shipTransitionsPaidToShipped() throws {
    var order = try Order(id: OrderId("ord-1"), lines: [line()])
    try order.pay()
    try order.ship()
    #expect(order.status == .shipped)
  }

  @Test func payAfterShipRaisesOrderAlreadyShipped() throws {
    var order = try Order(id: OrderId("ord-1"), lines: [line()])
    try order.pay()
    try order.ship()
    do {
      try order.pay()
      Issue.record("expected OrderAlreadyShipped")
    } catch is OrderAlreadyShipped {
      // expected
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func shipAfterShipRaisesOrderAlreadyShipped() throws {
    var order = try Order(id: OrderId("ord-1"), lines: [line()])
    try order.pay()
    try order.ship()
    do {
      try order.ship()
      Issue.record("expected OrderAlreadyShipped")
    } catch is OrderAlreadyShipped {
      // expected
    } catch {
      Issue.record("unexpected error \(error)")
    }
  }

  @Test func snapshotIsDetachedFromTheOriginal() throws {
    let order = try Order(id: OrderId("ord-1"), lines: [line()])
    var copy = order.snapshot()
    try copy.pay()
    copy.bumpVersion()
    #expect(order.status == .new)
    #expect(order.version == 0)
  }

  @Test func sequenceIdsAreNeverEmpty() {
    #expect(OrderId(sequence: 7).value == "ord-7")
  }
}
