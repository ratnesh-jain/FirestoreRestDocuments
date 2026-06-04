import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Logging

public struct FirestoreDocument: Sendable {
  public let config: FirestoreConfig
  public let parser: FirestoreDocumentParser

  public init(config: FirestoreConfig? = nil, parser: FirestoreDocumentParser = .init()) {
    self.config = config ?? FirestoreConfig.shared
    self.parser = parser
  }

  // MARK: - Static API (uses FirestoreConfig.shared)

  public static func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    try await FirestoreDocument().decode(type, from: path)
  }

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

  // MARK: - Instance API

  public func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    let data = try await fetch(from: path)
    return try parser.decode(T.self, from: data)
  }

  public func decode<T: Decodable>(
    _ type: T.Type,
    from path: String,
    using jsonDecoder: JSONDecoder
  ) async throws -> T {
    let data = try await fetch(from: path)
    return try jsonDecoder.firestoreDecode(T.self, from: data)
  }

  public func fetch(from path: String) async throws -> Data {
    Logger.firestoreRestDocuments.debug("Fetching from path: \(path)")
    let request = try config.makeRequest(path: path)
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      Logger.firestoreRestDocuments.error("Invalid response (not HTTP)")
      throw FirestoreParsingError.decodingFailed("Invalid response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      Logger.firestoreRestDocuments.warning("HTTP \(httpResponse.statusCode): \(body)")
      throw FirestoreParsingError.decodingFailed(
        "HTTP \(httpResponse.statusCode): \(body)"
      )
    }
    Logger.firestoreRestDocuments.debug("Response \(httpResponse.statusCode) (\(data.count) bytes)")
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
    Logger.firestoreRestDocuments.debug("Fetching page of \(T.self) from path: \(path)")
    var items = [URLQueryItem]()
    if let pageSize {
      items.append(URLQueryItem(name: "pageSize", value: String(pageSize)))
    }
    if let pageToken {
      items.append(URLQueryItem(name: "pageToken", value: pageToken))
    }
    let request = try config.makeRequest(path: path, queryItems: items)
    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw FirestoreParsingError.decodingFailed("Invalid response")
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      throw FirestoreParsingError.decodingFailed("HTTP \(httpResponse.statusCode): \(body)")
    }
    Logger.firestoreRestDocuments.debug("Response \(httpResponse.statusCode) (\(data.count) bytes)")
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
    Logger.firestoreRestDocuments.debug("Fetching all \(T.self) from path: \(path)")
    var allItems = [T]()
    var pageToken: String? = nil
    repeat {
      let page = try await fetchPage(type, from: path, pageSize: pageSize, pageToken: pageToken)
      allItems.append(contentsOf: page.items)
      pageToken = page.nextPageToken
    } while pageToken != nil
    return allItems
  }

  // MARK: - Batch Operations

  public func batchGet(
    documents: [String],
    mask: FirestoreDocumentMask? = nil
  ) async throws -> [FirestoreBatchGetResult] {
    Logger.firestoreRestDocuments.debug("BatchGet \(documents.count) document(s)")
    let fullPaths = documents.map { config.fullDocumentPath(for: $0) }
    var bodyDict: [String: Any] = ["documents": fullPaths]
    if let mask {
      bodyDict["mask"] = ["fieldPaths": mask.fieldPaths]
    }
    let body = try JSONSerialization.data(withJSONObject: bodyDict, options: [.sortedKeys])
    var request = config.makeRequest(url: config.batchGetURL)
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
    Logger.firestoreRestDocuments.debug("Commit \(writes.count) write(s)")
    let body = try buildCommitBody(writes: writes, transaction: transaction)
    var request = config.makeRequest(url: config.commitURL)
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
    Logger.firestoreRestDocuments.debug("BatchWrite \(writes.count) write(s)")
    let body = try buildBatchWriteBody(writes: writes, labels: labels)
    var request = config.makeRequest(url: config.batchWriteURL)
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
        Logger.firestoreRestDocuments.warning("Failed to decode batchGet result for \(doc.name): \(error)")
      }
    }
    return items
  }

  // MARK: - Private Helpers

  private func buildCommitBody(writes: [FirestoreWrite], transaction: String?) throws -> Data {
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

  private func buildBatchWriteBody(writes: [FirestoreWrite], labels: [String: String]?) throws -> Data {
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
      let fields = try JSONSerialization.jsonObject(with: fieldsData) as! [String: Any]
      return ["update": ["name": fullPath, "fields": fields]]

    case .update(let fieldsData, let updateMask, let exists):
      let fields = try JSONSerialization.jsonObject(with: fieldsData) as! [String: Any]
      var document: [String: Any] = ["name": fullPath, "fields": fields]
      if let updateMask {
        document["updateMask"] = ["fieldPaths": updateMask]
      }
      if let exists {
        document["currentDocument"] = ["exists": exists]
      }
      return ["update": document]
    }
  }
}
