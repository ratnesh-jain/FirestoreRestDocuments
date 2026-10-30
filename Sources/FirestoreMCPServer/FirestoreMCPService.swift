import FirestoreOperations
import FirestoreRestDocuments
import Foundation
import Logging
import MCP

/// Builds the read-only Firestore MCP server.
public enum FirestoreMCPService {
  public static let serverName = "frd-mcp"
  public static let serverVersion = "0.1.0"

  public static let instructions = """
    Read-only access to Cloud Firestore through the REST API. \
    Use firestore_list_collections to discover collection paths, \
    firestore_list_documents to browse a collection, and \
    firestore_get_document to read a specific document.
    """

  public static func makeServer(
    connection: ResolvedFirestoreConnection,
    logger: Logger? = nil
  ) async -> Server {
    let server = Server(
      name: serverName,
      version: serverVersion,
      title: "Firestore REST Documents",
      instructions: instructions,
      capabilities: .init(tools: .init())
    )
    let database = FirestoreDocument(
      config: connection.config,
      logLevel: connection.logLevel
    )

    await server.withMethodHandler(ListTools.self) { _ in
      .init(tools: FirestoreTools.all)
    }

    await server.withMethodHandler(CallTool.self) { params in
      await callTool(
        name: params.name,
        arguments: params.arguments,
        database: database
      )
    }

    return server
  }

  // MARK: - Dispatch

  static func callTool(
    name: String,
    arguments: [String: Value]?,
    database: FirestoreDocument
  ) async -> CallTool.Result {
    switch name {
    case FirestoreTools.getDocument:
      return await getDocument(arguments, database: database)
    case FirestoreTools.listDocuments:
      return await listDocuments(arguments, database: database)
    case FirestoreTools.listCollections:
      return await listCollections(arguments, database: database)
    default:
      return failure("Unknown tool '\(name)'.")
    }
  }

  // MARK: - Tools

  private static func getDocument(
    _ arguments: [String: Value]?,
    database: FirestoreDocument
  ) async -> CallTool.Result {
    do {
      let path = try FirestorePath.document(try requiredString("path", in: arguments))
      var queryItems: [URLQueryItem] = []
      if let mask = try optionalString("mask", in: arguments) {
        for field in try FirestorePath.parseMask(mask) {
          queryItems.append(URLQueryItem(name: "mask.fieldPaths", value: field))
        }
      }

      let data = try await database.fetch(from: path, queryItems: queryItems)
      let document = try JSONParsing.object(from: data, context: "document response")
      var result = try DocumentPayload.summary(fromWireDocument: document)
      result["path"] = path
      return success(result)
    } catch {
      return failure(message(for: error))
    }
  }

  private static func listDocuments(
    _ arguments: [String: Value]?,
    database: FirestoreDocument
  ) async -> CallTool.Result {
    do {
      let collection = try FirestorePath.collection(
        try requiredString("collection", in: arguments)
      )
      var queryItems: [URLQueryItem] = []
      if let pageSize = try pageSize(in: arguments) {
        queryItems.append(URLQueryItem(name: "pageSize", value: String(pageSize)))
      }
      if let pageToken = try optionalString("pageToken", in: arguments) {
        queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
      }

      let data = try await database.fetch(from: collection, queryItems: queryItems)
      let page = try JSONParsing.object(from: data, context: "list response")
      let documents = page["documents"] as? [[String: Any]] ?? []

      var result: [String: Any] = [
        "collection": collection,
        "documents": try documents.map { try DocumentPayload.summary(fromWireDocument: $0) },
      ]
      if let nextPageToken = page["nextPageToken"] as? String {
        result["nextPageToken"] = nextPageToken
      }
      return success(result)
    } catch {
      return failure(message(for: error))
    }
  }

  private static func listCollections(
    _ arguments: [String: Value]?,
    database: FirestoreDocument
  ) async -> CallTool.Result {
    do {
      let parent = try FirestorePath.parentDocument(
        try optionalString("parent", in: arguments)
      )
      let page = try await database.listCollectionIds(
        parent: parent,
        pageSize: try pageSize(in: arguments),
        pageToken: try optionalString("pageToken", in: arguments)
      )

      var result: [String: Any] = [
        "collections": page.collectionIds.map { id in
          parent.map { "\($0)/\(id)" } ?? id
        }
      ]
      if let parent {
        result["parent"] = parent
      }
      if let nextPageToken = page.nextPageToken {
        result["nextPageToken"] = nextPageToken
      }
      return success(result)
    } catch {
      return failure(message(for: error))
    }
  }

  // MARK: - Arguments

  private static func requiredString(
    _ key: String,
    in arguments: [String: Value]?
  ) throws -> String {
    guard let value = arguments?[key]?.stringValue,
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw FirestoreOperationError("Missing required argument '\(key)'.")
    }
    return value
  }

  private static func optionalString(
    _ key: String,
    in arguments: [String: Value]?
  ) throws -> String? {
    guard let value = arguments?[key] else { return nil }
    guard let string = value.stringValue else {
      throw FirestoreOperationError("Argument '\(key)' must be a string.")
    }
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func pageSize(in arguments: [String: Value]?) throws -> Int? {
    guard let value = arguments?["pageSize"] else { return nil }
    guard let pageSize = value.intValue else {
      throw FirestoreOperationError("Argument 'pageSize' must be an integer.")
    }
    guard (1...1000).contains(pageSize) else {
      throw FirestoreOperationError("Argument 'pageSize' must be between 1 and 1000.")
    }
    return pageSize
  }

  // MARK: - Results

  private static func success(_ object: [String: Any]) -> CallTool.Result {
    let data: Data
    do {
      data = try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
      )
    } catch {
      return failure("Could not encode the response: \(error.localizedDescription)")
    }
    let text = String(data: data, encoding: .utf8) ?? "{}"
    let structured = try? JSONDecoder().decode(Value.self, from: data)
    return CallTool.Result(
        content: [.text(text: text, annotations: nil, _meta: nil)],
      structuredContent: structured,
      isError: false
    )
  }

  private static func failure(_ message: String) -> CallTool.Result {
    CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
  }

  private static func message(for error: Error) -> String {
    if let error = error as? FirestoreOperationError {
      return error.message
    }
    return error.localizedDescription
  }
}
