import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Logging

public struct FirestoreDocument: Sendable {
  public let config: FirestoreConfig
  public let parser: FirestoreDocumentParser
  public let logLevel: Logger.Level

  public init(
    config: FirestoreConfig? = nil,
    parser: FirestoreDocumentParser = .init(),
    logLevel: Logger.Level? = nil
  ) {
    self.config = config ?? FirestoreConfig.shared
    self.parser = parser
    self.logLevel = logLevel ?? Logger.defaultFirestoreLogLevel
  }

  private var logger: Logger {
    var logger = Logger(label: "com.firestorerestdocuments")
    logger.logLevel = logLevel
    return logger
  }

  // MARK: - Static API (uses FirestoreConfig.shared)

  public static func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    try await FirestoreDocument().decode(type, from: path)
  }

  // MARK: - Instance API

  public func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    logger.debug("Decoding \(T.self) from path: \(path)")
    let data = try await fetch(from: path)
    logger.debug("Fetched \(data.count) bytes for path: \(path)")
    let bodyPreview = String(data: data.prefix(4096), encoding: .utf8) ?? "<non-utf8>"
    logger.debug("Response body preview: \(bodyPreview)")
    do {
      let result = try parser.decode(T.self, from: data)
      logger.debug("Successfully decoded \(T.self) from path: \(path)")
      return result
    } catch {
      let bodyStr = String(data: data, encoding: .utf8) ?? "<non-utf8>"
      logger.error("Failed to decode \(T.self) from path: \(path): \(error). Response body:\n\(bodyStr)")
      throw error
    }
  }

  public func decode<T: Decodable>(
    _ type: T.Type,
    from path: String,
    using jsonDecoder: JSONDecoder
  ) async throws -> T {
    logger.debug("Decoding \(T.self) from path: \(path) using JSONDecoder")
    let data = try await fetch(from: path)
    logger.debug("Fetched \(data.count) bytes for path: \(path)")
    let bodyPreview = String(data: data.prefix(4096), encoding: .utf8) ?? "<non-utf8>"
    logger.debug("Response body preview: \(bodyPreview)")
    do {
      let result = try jsonDecoder.firestoreDecode(T.self, from: data)
      logger.debug("Successfully decoded \(T.self) from path: \(path) using JSONDecoder")
      return result
    } catch {
      let bodyStr = String(data: data, encoding: .utf8) ?? "<non-utf8>"
      logger.error("Failed to decode \(T.self) from path: \(path) using JSONDecoder: \(error). Response body:\n\(bodyStr)")
      throw error
    }
  }

  public func fetch(from path: String) async throws -> Data {
    try await fetch(from: path, queryItems: [])
  }

  public func fetch(from path: String, queryItems: [URLQueryItem]) async throws -> Data {
    logger.debug("Fetching from path: \(path)")
    let accessToken = try await config.resolveAccessToken()
    let request = try config.makeRequest(path: path, queryItems: queryItems, accessToken: accessToken)
    logger.debug("Request URL: \(request.url?.absoluteString ?? "nil")")
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      logger.error("Invalid response (not HTTP)")
      throw FirestoreParsingError.decodingFailed("Invalid response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      logger.warning("HTTP \(httpResponse.statusCode): \(body)")
      throw FirestoreParsingError.decodingFailed(
        "HTTP \(httpResponse.statusCode): \(body)"
      )
    }
    logger.debug("Response \(httpResponse.statusCode) (\(data.count) bytes)")
    logger.debug("Response headers: \(httpResponse.allHeaderFields)")
    return data
  }

  // MARK: - Pagination

  public static func fetchPage<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int? = nil, pageToken: String? = nil
  ) async throws -> FirestorePage<T> {
    try await FirestoreDocument().fetchPage(type, from: path, pageSize: pageSize, pageToken: pageToken)
  }

  public func fetchPage<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int? = nil, pageToken: String? = nil
  ) async throws -> FirestorePage<T> {
    logger.debug("Fetching page of \(T.self) from path: \(path)")
    var items = [URLQueryItem]()
    if let pageSize {
      items.append(URLQueryItem(name: "pageSize", value: String(pageSize)))
    }
    if let pageToken {
      items.append(URLQueryItem(name: "pageToken", value: pageToken))
    }
    let accessToken = try await config.resolveAccessToken()
    let request = try config.makeRequest(path: path, queryItems: items, accessToken: accessToken)
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw FirestoreParsingError.decodingFailed("Invalid response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      throw FirestoreParsingError.decodingFailed("HTTP \(httpResponse.statusCode): \(body)")
    }
    logger.debug("Response \(httpResponse.statusCode) (\(data.count) bytes)")
    return try parser.decodePage(type, from: data)
  }

  public static func fetchAll<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int? = nil
  ) async throws -> [T] {
    try await FirestoreDocument().fetchAll(type, from: path, pageSize: pageSize)
  }

  public func fetchAll<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int? = nil
  ) async throws -> [T] {
    logger.debug("Fetching all \(T.self) from path: \(path)")
    var allItems = [T]()
    var pageToken: String? = nil
    repeat {
      let page = try await fetchPage(type, from: path, pageSize: pageSize, pageToken: pageToken)
      allItems.append(contentsOf: page.items)
      pageToken = page.nextPageToken
    } while pageToken != nil
    return allItems
  }

  // MARK: - Static API (batch)

  public static func batchGet(
    documents: [String],
    mask: FirestoreDocumentMask? = nil
  ) async throws -> [FirestoreBatchGetResult] {
    try await FirestoreDocument().batchGet(documents: documents, mask: mask)
  }

  public static func commit(
    writes: [FirestoreWrite],
    transaction: String? = nil
  ) async throws -> FirestoreCommitResponse {
    try await FirestoreDocument().commit(writes: writes, transaction: transaction)
  }

  public static func batchWrite(
    writes: [FirestoreWrite],
    labels: [String: String]? = nil
  ) async throws -> FirestoreBatchWriteResponse {
    try await FirestoreDocument().batchWrite(writes: writes, labels: labels)
  }

  // MARK: - Collections

  public static func listCollectionIds(
    parent: String? = nil,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) async throws -> FirestoreCollectionIdsPage {
    try await FirestoreDocument().listCollectionIds(
      parent: parent,
      pageSize: pageSize,
      pageToken: pageToken
    )
  }

  public func listCollectionIds(
    parent: String? = nil,
    pageSize: Int? = nil,
    pageToken: String? = nil
  ) async throws -> FirestoreCollectionIdsPage {
    logger.debug("ListCollectionIds under \(parent ?? "root")")
    var body: [String: Any] = [:]
    if let pageSize { body["pageSize"] = pageSize }
    if let pageToken { body["pageToken"] = pageToken }
    let bodyData = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    let accessToken = try await config.resolveAccessToken()
    var request = config.makeRequest(
      url: try config.listCollectionIdsURL(parentPath: parent),
      accessToken: accessToken
    )
    request.httpMethod = "POST"
    request.httpBody = bodyData

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw FirestoreParsingError.decodingFailed("Invalid response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      throw FirestoreParsingError.decodingFailed("HTTP \(httpResponse.statusCode): \(body)")
    }

    return try JSONDecoder().decode(FirestoreCollectionIdsPage.self, from: data)
  }

  // MARK: - Batch Operations

  public func batchGet(
    documents: [String],
    mask: FirestoreDocumentMask? = nil
  ) async throws -> [FirestoreBatchGetResult] {
    logger.debug("BatchGet \(documents.count) document(s)")
    let fullPaths = documents.map { config.fullDocumentPath(for: $0) }
    var bodyDict: [String: Any] = ["documents": fullPaths]
    if let mask {
      bodyDict["mask"] = ["fieldPaths": mask.fieldPaths]
    }
    let body = try JSONSerialization.data(withJSONObject: bodyDict, options: [.sortedKeys])
    let accessToken = try await config.resolveAccessToken()
    var request = config.makeRequest(url: config.batchGetURL, accessToken: accessToken)
    request.httpMethod = "POST"
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw FirestoreParsingError.decodingFailed("Invalid response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      throw FirestoreParsingError.decodingFailed("HTTP \(httpResponse.statusCode): \(body)")
    }

    return try parser.decodeBatchGetResponse(from: data)
  }

  public func commit(
    writes: [FirestoreWrite],
    transaction: String? = nil
  ) async throws -> FirestoreCommitResponse {
    logger.debug("Commit \(writes.count) write(s)")
    let body = try makeCommitBody(writes: writes, transaction: transaction)
    let accessToken = try await config.resolveAccessToken()
    var request = config.makeRequest(url: config.commitURL, accessToken: accessToken)
    request.httpMethod = "POST"
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw FirestoreParsingError.decodingFailed("Invalid response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      throw FirestoreParsingError.decodingFailed("HTTP \(httpResponse.statusCode): \(body)")
    }

    return try JSONDecoder().decode(FirestoreCommitResponse.self, from: data)
  }

  public func batchWrite(
    writes: [FirestoreWrite],
    labels: [String: String]? = nil
  ) async throws -> FirestoreBatchWriteResponse {
    logger.debug("BatchWrite \(writes.count) write(s)")
    let body = try makeBatchWriteBody(writes: writes, labels: labels)
    let accessToken = try await config.resolveAccessToken()
    var request = config.makeRequest(url: config.batchWriteURL, accessToken: accessToken)
    request.httpMethod = "POST"
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw FirestoreParsingError.decodingFailed("Invalid response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      throw FirestoreParsingError.decodingFailed("HTTP \(httpResponse.statusCode): \(body)")
    }

    return try JSONDecoder().decode(FirestoreBatchWriteResponse.self, from: data)
  }

  // MARK: - Variadic-generic batchGet

  public func batchGet<T: Decodable & Sendable>(
    _ type: T.Type,
    documents: [String],
    mask: FirestoreDocumentMask? = nil
  ) async throws -> [Document<T>] {
    let results = try await batchGet(documents: documents, mask: mask)
    return decodeBatchGetSegment(T.self, from: results)
  }

  public func batchGet<T1: Decodable & Sendable, T2: Decodable & Sendable>(
    _ type1: T1.Type, documentPaths: [String],
    _ type2: T2.Type, documentPaths paths2: [String],
    mask: FirestoreDocumentMask? = nil
  ) async throws -> ([Document<T1>], [Document<T2>]) {
    let allPaths = documentPaths + paths2
    let results = try await batchGet(documents: allPaths, mask: mask)
    let mid = documentPaths.count
    let seg1 = Array(results[0..<mid])
    let seg2 = Array(results[mid...])
    return (
      decodeBatchGetSegment(T1.self, from: seg1),
      decodeBatchGetSegment(T2.self, from: seg2)
    )
  }

  private func decodeBatchGetSegment<T: Decodable & Sendable>(
    _ type: T.Type,
    from results: [FirestoreBatchGetResult]
  ) -> [Document<T>] {
    var items: [Document<T>] = []
    for result in results {
      guard case .found(let doc) = result else { continue }
      let value = FirestoreValue.document(name: doc.name, fields: doc.fields)
      var userInfo: [CodingUserInfoKey: Any] = [:]
      userInfo[.documentNameUserInfoKey] = doc.name
      let decoder = _FirestoreDecoder(value: value, userInfo: userInfo)
      do {
        items.append(try Document<T>(from: decoder))
      } catch {
        logger.warning("Failed to decode batchGet result for \(doc.name): \(error)")
      }
    }
    return items
  }

  // MARK: - Private Helpers

  /// Builds the JSON body used by the `commit` endpoint. Useful for inspecting
  /// or logging the exact request payload (for example, a CLI `--dry-run`).
  public func makeCommitBody(writes: [FirestoreWrite], transaction: String? = nil) throws -> Data {
    var writesJSON: [[String: Any]] = []
    for write in writes {
      writesJSON.append(try serializeWrite(write))
    }
    var body: [String: Any] = ["writes": writesJSON]
    if let transaction {
      body["transaction"] = transaction
    }
    return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
  }

  /// Builds the JSON body used by the `batchWrite` endpoint.
  public func makeBatchWriteBody(writes: [FirestoreWrite], labels: [String: String]? = nil) throws -> Data {
    var writesJSON: [[String: Any]] = []
    for write in writes {
      writesJSON.append(try serializeWrite(write))
    }
    var body: [String: Any] = ["writes": writesJSON]
    if let labels {
      body["labels"] = labels
    }
    return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
  }

  private func serializeWrite(_ write: FirestoreWrite) throws -> [String: Any] {
    let fullPath = config.fullDocumentPath(for: write.documentPath)
    switch write.storage {
    case .delete:
      return ["delete": fullPath]

    case .create(let fieldsData):
      let fields = try fieldsDictionary(from: fieldsData)
      return [
        "update": ["name": fullPath, "fields": fields],
        "currentDocument": ["exists": false],
      ]

    case .update(let fieldsData, let updateMask, let exists):
      let fields = try fieldsDictionary(from: fieldsData)
      var writeJSON: [String: Any] = ["update": ["name": fullPath, "fields": fields]]
      if let updateMask {
        writeJSON["updateMask"] = ["fieldPaths": updateMask]
      }
      if let exists {
        writeJSON["currentDocument"] = ["exists": exists]
      }
      return writeJSON
    }
  }

  private func fieldsDictionary(from data: Data) throws -> [String: Any] {
    guard let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw FirestoreParsingError.encodingFailed("Encoded document fields must be a JSON object")
    }
    return fields
  }
}

