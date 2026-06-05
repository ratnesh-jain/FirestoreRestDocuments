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
    logger.debug("Fetching from path: \(path)")
    let request = try config.makeRequest(path: path)
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
    let request = try config.makeRequest(path: path, queryItems: items)
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
}
