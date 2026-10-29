import FirestoreOperations
import ArgumentParser
import Foundation
import FirestoreRestDocuments

struct DeleteCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "delete",
    abstract: "Delete one or more documents.",
    discussion: "All documents are deleted atomically in a single commit."
  )

  @Argument(help: "One or more document paths.")
  var paths: [String]

  @Flag(name: .long, help: "Print the request instead of sending it.")
  var dryRun = false

  @OptionGroup var global: GlobalOptions

  public init() {}

  func validate() throws {
    guard !paths.isEmpty else {
      throw CLIError("Provide at least one document path.")
    }
  }

  func run() async throws {
    let context = try CLIContext(global, requiresCredentials: !dryRun)
    let documentPaths = try paths.map(FirestorePath.document)
    let writes = documentPaths.map { FirestoreWrite.delete(at: $0) }

    if dryRun {
      try context.writeDryRun(writes: writes, labels: nil, atomic: true)
      return
    }

    let response = try await context.database.commit(writes: writes)
    try context.writeCommitResult(response, operation: "delete", paths: documentPaths)
  }
}
