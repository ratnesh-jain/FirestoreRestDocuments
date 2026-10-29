import FirestoreOperations
import ArgumentParser
import Foundation
import FirestoreRestDocuments

struct UpdateCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update fields in an existing document.",
    discussion: """
    By default only the provided top-level fields are written (a merge-style \
    update); use --replace to replace the whole document. Use --mask to update \
    exact (including dotted) field paths, and --if-exists to fail when the \
    document is missing.

    Data can be a flat JSON object or a Firestore REST document ({"fields": ...}).
    """
  )

  @Argument(help: "Document path, for example users/alice.")
  var path: String

  @Option(name: .long, help: "JSON document data.")
  var data: String?

  @Option(name: [.customShort("f"), .long], help: "Path to a JSON file, or '-' for stdin.")
  var file: String?

  @Option(name: .long, help: "Comma-separated field paths to update.")
  var mask: String?

  @Flag(name: .long, help: "Replace the whole document instead of merging fields.")
  var replace = false

  @Flag(name: .customLong("if-exists"), help: "Fail if the document does not exist.")
  var ifExists = false

  @Flag(name: .long, help: "Print the request instead of sending it.")
  var dryRun = false

  @OptionGroup var global: GlobalOptions

  public init() {}

  func validate() throws {
    if replace && mask != nil {
      throw CLIError("--replace and --mask cannot be used together.")
    }
  }

  func run() async throws {
    let context = try CLIContext(global, requiresCredentials: !dryRun)
    let documentPath = try FirestorePath.document(path)
    let fields = try DocumentPayload.fields(
      from: DataInput.load(data: data, file: file),
      config: context.config
    )

    let updateMask: [String]?
    if let mask {
      updateMask = try FirestorePath.parseMask(mask)
    } else if replace {
      updateMask = nil
    } else {
      updateMask = try WriteSupport.mask(from: fields)
    }

    let write = try WriteSupport.makeWrite(
      path: documentPath,
      fields: fields,
      updateMask: updateMask,
      createOnly: false,
      ifExists: ifExists
    )

    if dryRun {
      try context.writeDryRun(writes: [write], labels: nil, atomic: true)
      return
    }

    let response = try await context.database.commit(writes: [write])
    try context.writeCommitResult(response, operation: "update", path: documentPath)
  }
}
