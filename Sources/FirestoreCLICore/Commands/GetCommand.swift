import ArgumentParser
import Foundation
import FirestoreRestDocuments

struct GetCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "get",
    abstract: "Fetch a single document.",
    discussion: """
    Prints the document's fields as JSON. Use --raw to print the unmodified \
    Firestore REST response (useful for round-tripping with `set --file`).
    """
  )

  @Argument(help: "Document path, for example users/alice.")
  var path: String

  @Flag(name: .long, help: "Print the raw Firestore REST response.")
  var raw = false

  @OptionGroup var global: GlobalOptions

  public init() {}

  func run() async throws {
    let context = try CLIContext(global)
    let documentPath = try FirestorePath.document(path)
    let data = try await context.database.fetch(from: documentPath)
    let response = try JSONParsing.object(from: data, context: "document response")

    if response["documents"] != nil {
      throw CLIError(
        "'\(documentPath)' is a collection. Use `frd list \(documentPath)` instead."
      )
    }

    if raw {
      try context.writeJSON(response)
      return
    }

    let fields = response["fields"] as? [String: Any] ?? [:]
    try context.writeJSON(try DocumentPayload.normalizedFields(fields))
  }
}
