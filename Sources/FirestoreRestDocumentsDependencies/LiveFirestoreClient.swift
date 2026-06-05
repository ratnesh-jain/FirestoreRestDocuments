import Foundation
import FirestoreRestDocuments
import Logging

public struct LiveFirestoreClient: FirestoreClient {
  public let config: FirestoreConfig
  public let parser: FirestoreDocumentParser
  public let logLevel: Logger.Level

  public init(
    config: FirestoreConfig,
    parser: FirestoreDocumentParser = .init(),
    logLevel: Logger.Level? = nil
  ) {
    self.config = config
    self.parser = parser
    self.logLevel = logLevel ?? Logger.defaultFirestoreLogLevel
  }

  public func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    let db = FirestoreDocument(config: config, parser: parser, logLevel: logLevel)
    return try await db.decode(type, from: path)
  }

  public func fetch(from path: String) async throws -> Data {
    let db = FirestoreDocument(config: config, parser: parser, logLevel: logLevel)
    return try await db.fetch(from: path)
  }

  public func encode<T: Encodable>(_ value: T, documentName: String?) throws -> Data {
    try parser.encode(value, documentName: documentName)
  }

  public func fetchPage<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int?, pageToken: String?
  ) async throws -> FirestorePage<T> {
    let db = FirestoreDocument(config: config, parser: parser, logLevel: logLevel)
    return try await db.fetchPage(type, from: path, pageSize: pageSize, pageToken: pageToken)
  }
}
