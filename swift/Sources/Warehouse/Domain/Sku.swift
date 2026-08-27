/// Shared UTF-8 byte length limit for a normalized SKU code.
public let skuMaxUtf8Bytes = 64

/// A stock-keeping-unit code, normalized on creation.
public struct Sku: Equatable, Hashable, Sendable, CustomStringConvertible {
  public let code: String

  /// Strip only ASCII space, tab, CR, and LF from both ends, then validate.
  public init(_ code: String) throws {
    let trimmed = trimAsciiEdges(code)
    if trimmed.isEmpty {
      throw InvalidOrder("sku code must be non-empty")
    }
    if trimmed.utf8.count > skuMaxUtf8Bytes {
      throw InvalidOrder("sku code exceeds \(skuMaxUtf8Bytes) UTF-8 bytes")
    }
    self.code = trimmed
  }

  public var description: String { code }
}

func trimAsciiEdges(_ code: String) -> String {
  // Walk Unicode scalars, not Character. Swift treats U+000D U+000A as one
  // grapheme cluster, which would skip CR/LF if we compared Character values.
  func isEdge(_ scalar: Unicode.Scalar) -> Bool {
    scalar == "\u{0020}" || scalar == "\u{0009}" || scalar == "\u{000D}" || scalar == "\u{000A}"
  }
  let scalars = code.unicodeScalars
  var start = scalars.startIndex
  var end = scalars.endIndex
  while start < end, isEdge(scalars[start]) {
    start = scalars.index(after: start)
  }
  while end > start {
    let previous = scalars.index(before: end)
    if !isEdge(scalars[previous]) {
      break
    }
    end = previous
  }
  return String(scalars[start..<end])
}
