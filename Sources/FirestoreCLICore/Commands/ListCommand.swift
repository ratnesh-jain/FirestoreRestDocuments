import ArgumentParser
import Foundation
import FirestoreRestDocuments

struct ListCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List the documents in a collection.",
    discussion: """
    Prints a JSON array of { id, name, createTime, updateTime, data } objects. \
    By default only one page is returned; pass --all to follow every page, or \
    --limit to cap the number of documents.
    """
  )

  @Argument(help: "Collection path, for example users or users/alice/orders.")
  var path: String

  @Option(name: .long, help: "Number of documents per page (1...1000).")
  var pageSize: Int?

  @Option(name: .long, help: "Resume from a previous response's nextPageToken.")
  var pageToken: String?

  @Flag(name: .long, help: "Follow nextPageToken until every document has been read.")
  var all = false

  @Option(name: .long, help: "Stop after this many documents.")
  var limit: Int?

  @Flag(name: .long, help: "Print the raw Firestore REST documents.")
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
    let collectionPath = try FirestorePath.collection(path)

    let fetchAllPages = all || limit != nil
    var documents: [[String: Any]] = []
    var nextPageToken: String? = pageToken
    var responseToken: String?

    repeat {
      var queryItems: [URLQueryItem] = []
      if let size = pageSizeForRequest(limit: limit, alreadyFetched: documents.count) {
        queryItems.append(URLQueryItem(name: "pageSize", value: String(size)))
      }
      if let nextPageToken {
        queryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
      }

      let data = try await context.database.fetch(from: collectionPath, queryItems: queryItems)
      let page = try JSONParsing.object(from: data, context: "list response")
      let pageDocuments = page["documents"] as? [[String: Any]] ?? []
      documents.append(contentsOf: pageDocuments)

      let token = page["nextPageToken"] as? String
      responseToken = token
      nextPageToken = token

      if let limit, documents.count >= limit {
        documents = Array(documents.prefix(limit))
        break
      }

      if limit != nil {
        continue
      }
      if !fetchAllPages {
        break
      }
    } while nextPageToken != nil

    if raw {
      var result: [String: Any] = ["documents": documents]
      if !fetchAllPages, let responseToken {
        result["nextPageToken"] = responseToken
      }
      try context.writeJSON(result)
      return
    }

    let items: [[String: Any]] = try documents.map { document in
      var item: [String: Any] = [:]
      if let name = document["name"] as? String {
        item["id"] = FirestorePath.documentID(fromFullName: name)
        item["name"] = name
      }
      if let createTime = document["createTime"] as? String {
        item["createTime"] = createTime
      }
      if let updateTime = document["updateTime"] as? String {
        item["updateTime"] = updateTime
      }
      let fields = document["fields"] as? [String: Any] ?? [:]
      item["data"] = try DocumentPayload.normalizedFields(fields)
      return item
    }
    try context.writeJSON(items)
  }

  private func pageSizeForRequest(limit: Int?, alreadyFetched: Int) -> Int? {
    PageSizing.size(
      requested: pageSize,
      limit: limit,
      alreadyFetched: alreadyFetched,
      followAll: all
    )
  }
}
