import FirestoreOperations
import ArgumentParser
import Foundation
import FirestoreRestDocuments

struct SetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "set",
    abstract: "Create a document or replace it entirely.",
    discussion: """
    Reads document data from --data, --file, or stdin. By default the document \
    is replaced (fields that are not provided are removed). Use --merge to only \
    write the provided top-level fields, or --mask to update exact field paths.

    Data can be a flat JSON object ({"name": "Alice"}) or a Firestore REST \
    document ({"fields": {...}}), which makes `get --raw` output reusable.
    Typed values can be written with $timestamp, $reference, $geopoint, $bytes, \
    $integer, $double, and $literal.
    """
  )

  @Argument(help: "Document path (users/alice) or collection path (users, with --id).")
  var path: String

  @Option(name: .long, help: "JSON document data.")
  var data: String?

  @Option(name: [.customShort("f"), .long], help: "Path to a JSON file, or '-' for stdin.")
  var file: String?

  @Option(name: .long, help: "Document ID to append when PATH is a collection.")
  var id: String?

  @Flag(name: .long, help: "Merge the provided top-level fields instead of replacing the document.")
  var merge = false

  @Option(name: .long, help: "Comma-separated field paths to write.")
  var mask: String?

  @Flag(name: .customLong("create-only"), help: "Fail if the document already exists.")
  var createOnly = false

  @Flag(name: .customLong("if-exists"), help: "Fail if the document does not exist.")
  var ifExists = false

  @Flag(name: .long, help: "Print the request instead of sending it.")
  var dryRun = false

  @OptionGroup var global: GlobalOptions

  public init() {}

  func validate() throws {
    if merge && mask != nil {
      throw CLIError("--merge and --mask cannot be used together.")
    }
    if createOnly && (merge || mask != nil) {
      throw CLIError("--create-only cannot be combined with --merge or --mask.")
    }
    if createOnly && ifExists {
      throw CLIError("--create-only and --if-exists cannot be used together.")
    }
  }

  func run() async throws {
    let context = try CLIContext(global, requiresCredentials: !dryRun)
    let documentPath = try FirestorePath.writeTarget(path, id: id, generateID: true)
    let fields = try DocumentPayload.fields(
      from: DataInput.load(data: data, file: file),
      config: context.config
    )

    let updateMask: [String]?
    if let mask {
      updateMask = try FirestorePath.parseMask(mask)
    } else if merge {
      updateMask = try WriteSupport.mask(from: fields)
    } else {
      updateMask = nil
    }

    let write = try WriteSupport.makeWrite(
      path: documentPath,
      fields: fields,
      updateMask: updateMask,
      createOnly: createOnly,
      ifExists: ifExists
    )

    if dryRun {
      try context.writeDryRun(writes: [write], labels: nil, atomic: true)
      return
    }

    let response = try await context.database.commit(writes: [write])
    try context.writeCommitResult(
      response,
      operation: createOnly ? "create" : "set",
      path: documentPath
    )
  }
}
