import FirestoreOperations
import ArgumentParser
import Foundation
import FirestoreRestDocuments

struct BatchWriteCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "batch-write",
    abstract: "Apply a batch of create, set, update, and delete operations.",
    discussion: """
    Reads a JSON array of operations from --file (or stdin). Operations are \
    committed atomically by default; pass --non-atomic to use the batchWrite \
    endpoint, which reports a per-write status.

    Example file:
      [
        {"op": "create", "path": "users/u1", "data": {"name": "Alice"}},
        {"op": "update", "path": "users/u1", "data": {"name": "Bob"}, "mask": ["name"]},
        {"op": "delete", "path": "users/u2"}
      ]
    """
  )

  @Option(name: [.customShort("f"), .long], help: "Batch JSON file, or '-' for stdin. Defaults to stdin.")
  var file: String?

  @Option(name: .customLong("label"), help: "Label as key=value. May be repeated; requires --non-atomic.")
  var labels: [String] = []

  @Flag(name: .customLong("non-atomic"), help: "Use batchWrite instead of commit.")
  var nonAtomic = false

  @Flag(name: .long, help: "Print the request instead of sending it.")
  var dryRun = false

  @OptionGroup var global: GlobalOptions

  public init() {}

  func validate() throws {
    if !labels.isEmpty && !nonAtomic {
      throw CLIError("--label can only be used with --non-atomic.")
    }
  }

  func run() async throws {
    let context = try CLIContext(global, requiresCredentials: !dryRun)
    let data = try DataInput.load(data: nil, file: file)
    let json = try JSONParsing.any(from: data, context: "batch file")
    let writes = try BatchWriteFile.writes(from: json, config: context.config)
    let labelMap = try WriteSupport.parseLabels(labels)
    let resolvedLabels = labelMap.isEmpty ? nil : labelMap

    if dryRun {
      try context.writeDryRun(writes: writes, labels: resolvedLabels, atomic: !nonAtomic)
      return
    }

    if nonAtomic {
      let response = try await context.database.batchWrite(writes: writes, labels: resolvedLabels)
      try context.writeEncodable(response)
      return
    }

    let response = try await context.database.commit(writes: writes)
    try context.writeCommitResult(
      response,
      operation: "batch-write",
      paths: writes.map(\.documentPath)
    )
  }
}
