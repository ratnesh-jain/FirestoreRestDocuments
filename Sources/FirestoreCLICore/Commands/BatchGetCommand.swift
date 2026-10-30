import FirestoreOperations
import ArgumentParser
import Foundation
import FirestoreRestDocuments

struct BatchGetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "batch-get",
    abstract: "Fetch multiple documents in one request.",
    discussion: """
    Prints a JSON array in the same order as the requested paths. Each entry has \
    "found": true and a "data" object, or "found": false when the document does \
    not exist.
    """
  )

  @Argument(help: "One or more document paths.")
  var paths: [String]

  @Option(name: .long, help: "Comma-separated field paths to return.")
  var mask: String?

  @OptionGroup var global: GlobalOptions

  public init() {}

  func validate() throws {
    guard !paths.isEmpty else {
      throw CLIError("Provide at least one document path.")
    }
  }

  func run() async throws {
    let context = try CLIContext(global)
    let documentPaths = try paths.map(FirestorePath.document)
    let documentMask = try mask.map { FirestoreDocumentMask(fieldPaths: try FirestorePath.parseMask($0)) }

    let results = try await context.database.batchGet(documents: documentPaths, mask: documentMask)

    var output: [[String: Any]] = []
    for (index, result) in results.enumerated() {
      let requestedPath = index < documentPaths.count ? documentPaths[index] : ""
      switch result {
      case .found(let document):
        var item: [String: Any] = [
          "path": requestedPath,
          "found": true,
          "id": FirestorePath.documentID(fromFullName: document.name),
          "name": document.name,
          "data": document.fields.mapValues(DocumentPayload.flatValue),
        ]
        if let createTime = document.createTime {
          item["createTime"] = createTime
        }
        if let updateTime = document.updateTime {
          item["updateTime"] = updateTime
        }
        output.append(item)

      case .missing:
        output.append(["path": requestedPath, "found": false])
      }
    }

    try context.writeJSON(output)
  }
}
