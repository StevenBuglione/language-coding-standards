import Testing
import Warehouse

@Suite("Quantity")
struct QuantityTests {
  @Test func acceptsStrictlyPositiveValue() throws {
    #expect(try Quantity(1).value == 1)
  }

  @Test func rejectsZero() {
    expectInvalidOrder({ _ = try Quantity(0) }, contains: "strictly positive")
  }

  @Test func rejectsNegative() {
    expectInvalidOrder({ _ = try Quantity(-3) }, contains: "strictly positive")
  }

  @Test func rejectsAboveMax() {
    expectInvalidOrder({ _ = try Quantity(quantityMax + 1) }, contains: "exceeds")
  }

  @Test func acceptsSharedMaximum() throws {
    #expect(try Quantity(quantityMax).value == quantityMax)
  }
}
