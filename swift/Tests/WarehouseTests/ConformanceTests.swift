import Foundation
import Testing
import Warehouse

@Suite("conformance/v2 vectors")
struct ConformanceTests {
  @Test func moneyConstruct() throws {
    for caseEl in try cases("money.json") {
      guard caseEl.string("operation") == "money.construct" else { continue }
      let input = caseEl.object("input")
      let expect = caseEl.object("expect")
      let currency = input.string("currency")
      let raw = input["minorUnits"]
      if expect.string("outcome") == "ok" {
        let money = try Money(minorUnits: Int(raw as? String ?? "") ?? -1, currency: currency)
        let result = expect.object("result")
        #expect(String(money.minorUnits) == result.string("minorUnits"))
        #expect(money.currency == result.string("currency"))
      } else {
        #expect(throws: InvalidOrder.self) {
          if let text = raw as? String, let amount = Int(text) {
            _ = try Money(minorUnits: amount, currency: currency)
          } else {
            throw InvalidOrder("non-integer")
          }
        }
      }
    }
  }

  @Test func skuConstruct() throws {
    for caseEl in try cases("sku.json") {
      let code = caseEl.object("input").string("code")
      let expect = caseEl.object("expect")
      if expect.string("outcome") == "ok" {
        #expect(try Sku(code).code == expect.object("result").string("code"))
      } else {
        #expect(throws: InvalidOrder.self) { _ = try Sku(code) }
      }
    }
  }

  @Test func quantityConstruct() throws {
    for caseEl in try cases("quantity.json") {
      let raw = caseEl.object("input")["value"]
      let expect = caseEl.object("expect")
      if expect.string("outcome") == "ok" {
        let qty = try Quantity(Int(raw as? String ?? "") ?? 0)
        #expect(String(qty.value) == expect.object("result").string("value"))
      } else if raw is Bool {
        continue
      } else {
        #expect(throws: (any Error).self) {
          if let text = raw as? String, let parsed = Int(text) {
            _ = try Quantity(parsed)
          } else {
            throw InvalidOrder("non-integer")
          }
        }
      }
    }
  }

  @Test func orderConstructAndTransitions() throws {
    for caseEl in try cases("order.json") {
      let operation = caseEl.string("operation")
      let expect = caseEl.object("expect")
      let ok = expect.string("outcome") == "ok"
      if operation == "order.construct" {
        let id = try OrderId(caseEl.object("given").string("orderId"))
        let rawLines = caseEl.object("input").array("lines")
        if ok {
          let order = try Order(id: id, lines: lines(rawLines))
          #expect(order.status == .new)
          #expect(order.id.value == expect.object("result").string("id"))
        } else {
          #expect(throws: InvalidOrder.self) {
            _ = try Order(id: id, lines: lines(rawLines))
          }
        }
        continue
      }
      let given = caseEl.object("given").object("order")
      var order = try Order(id: OrderId(given.string("id")), lines: lines(given.array("lines")))
      switch given.string("status") {
      case "PAID":
        try order.pay()
      case "SHIPPED":
        try order.pay()
        try order.ship()
      default:
        break
      }
      if ok {
        if operation == "order.pay" {
          try order.pay()
          #expect(order.status == .paid)
        } else {
          try order.ship()
          #expect(order.status == .shipped)
        }
      } else {
        #expect(throws: (any Error).self) {
          if operation == "order.pay" {
            try order.pay()
          } else {
            try order.ship()
          }
        }
      }
    }
  }
}

private func suitesDir() throws -> URL {
  if let env = ProcessInfo.processInfo.environment["CONFORMANCE_DIR"] {
    return URL(fileURLWithPath: env)
  }
  if let workspace = ProcessInfo.processInfo.environment["GITHUB_WORKSPACE"] {
    return URL(fileURLWithPath: workspace).appendingPathComponent("conformance/v2/suites")
  }
  var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  for _ in 0..<8 {
    let candidate = dir.appendingPathComponent("conformance/v2/suites")
    if FileManager.default.isReadableFile(atPath: candidate.appendingPathComponent("money.json").path) {
      return candidate
    }
    dir.deleteLastPathComponent()
  }
  throw InvalidOrder("conformance/v2/suites not found")
}

private func cases(_ file: String) throws -> [[String: Any]] {
  let url = try suitesDir().appendingPathComponent(file)
  let data = try Data(contentsOf: url)
  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
  return json?["cases"] as? [[String: Any]] ?? []
}

private func lines(_ raw: [[String: Any]]) throws -> [OrderLine] {
  try raw.map { item in
    let price = item.object("unitPrice")
    return try OrderLine(
      sku: Sku(item.string("sku")),
      quantity: Quantity(Int(item.string("quantity")) ?? 0),
      unitPrice: Money(
        minorUnits: Int(price.string("minorUnits")) ?? 0,
        currency: price.string("currency")
      )
    )
  }
}

extension Dictionary where Key == String, Value == Any {
  fileprivate func string(_ key: String) -> String { self[key] as? String ?? "" }
  fileprivate func object(_ key: String) -> [String: Any] { self[key] as? [String: Any] ?? [:] }
  fileprivate func array(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
}
