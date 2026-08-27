import Foundation
import Testing

@Suite("architecture")
struct ArchitectureTests {
  @Test func domainSourcesDoNotMentionApplicationOrAdapters() throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("Sources/Warehouse/Domain")
    let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
    for file in files where file.hasSuffix(".swift") {
      let text = try String(contentsOfFile: root.appendingPathComponent(file).path, encoding: .utf8)
      #expect(!text.contains("PlaceOrderUseCase"), "\(file) mentions application type")
      #expect(!text.contains("InventoryGateway"), "\(file) mentions adapter port")
      #expect(!text.contains("InMemory"), "\(file) mentions adapter type")
    }
  }
}
