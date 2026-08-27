import Testing
import Warehouse

@Suite("property")
struct PropertyTests {
  @Test func moneyAdditionIsCommutative() throws {
    let amounts = [0, 1, 17, 250, 1_000_000]
    for left in amounts {
      for right in amounts {
        let a = try Money(minorUnits: left, currency: "USD")
        let b = try Money(minorUnits: right, currency: "USD")
        #expect(try a.add(b) == b.add(a))
      }
    }
  }

  @Test func timesZeroIsZero() throws {
    let money = try Money(minorUnits: 300, currency: "EUR")
    #expect(try money.times(0) == Money(minorUnits: 0, currency: "EUR"))
  }
}
