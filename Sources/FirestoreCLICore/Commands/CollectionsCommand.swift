import ArgumentParser
import Foundation
import FirestoreRestDocuments

struct CollectionsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "collections",
    abstract: "List the collections at the database root or under a document.",
    discussion: """
    Prints a JSON array of collection paths. By default the top-level \
    collections are listed; pass --parent to list the subcollections of a \
    document. By default only one page is returned; pass --all to follow every \
    page, or --limit to cap the number of collections.
    """
  )

  @Option(
    name: .long,
    help: "Document path whose subcollections should be listed. Defaults to the database root."
  )
  var parent: String?

  @Option(name: .long, help: "Number of collections per page (1...1000).")
  var pageSize: Int?

  @Option(name: .long, help: "Resume from a previous response's nextPageToken.")
  var pageToken: String?

  @Flag(name: .long, help: "Follow nextPageToken until every collection has been read.")
  var all = false

  @Option(name: .long, help: "Stop after this many collections.")
  var limit: Int?

  @Flag(name: .long, help: "Print the raw listCollectionIds response.")
  var raw = false

  @OptionGroup var global: GlobalOptions

  public init() {}

  func validate() throws {
    if let pageSize, !(1...1000).contains(pageSize) {
      throw CLIError("--page-size must be between 1 and 1000.")
    }
    if let limit, limit < 1 {
      throw CLIError("--limit must be greater than 0.")
    }
  }

  func run() async throws {
    let context = try CLIContext(global)
    let parentPath = try FirestorePath.parentDocument(parent)

    let followAll = all || limit != nil
    var collectionIds: [String] = []
    var nextPageToken: String? = pageToken
    var responseToken: String?

    repeat {
      let size = PageSizing.size(
        requested: pageSize,
        limit: limit,
        alreadyFetched: collectionIds.count,
        followAll: all
      )
      let page = try await context.database.listCollectionIds(
        parent: parentPath,
        pageSize: size,
        pageToken: nextPageToken
      )
      collectionIds.append(contentsOf: page.collectionIds)

      responseToken = page.nextPageToken
      nextPageToken = page.nextPageToken

      if let limit, collectionIds.count >= limit {
        collectionIds = Array(collectionIds.prefix(limit))
        break
      }

      if limit != nil {
        continue
      }
      if !followAll {
        break
      }
    } while nextPageToken != nil

    if raw {
      var result: [String: Any] = ["collectionIds": collectionIds]
      if !followAll, let responseToken {
        result["nextPageToken"] = responseToken
      }
      try context.writeJSON(result)
      return
    }

    let paths = collectionIds.map { id in
      parentPath.map { "\($0)/\(id)" } ?? id
    }
    try context.writeJSON(paths)
  }
}
