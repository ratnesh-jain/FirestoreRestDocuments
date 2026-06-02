import Foundation
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
}
