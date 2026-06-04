import Foundation
import FirestoreRestDocuments

public struct LiveFirestoreClient: FirestoreClient {
  public let config: FirestoreConfig
  public let parser: FirestoreDocumentParser

  public init(config: FirestoreConfig, parser: FirestoreDocumentParser = .init()) {
    self.config = config
    self.parser = parser
  }

  public func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    let db = FirestoreDocument(config: config, parser: parser)
    return try await db.decode(type, from: path)
  }

  public func fetch(from path: String) async throws -> Data {
    let db = FirestoreDocument(config: config, parser: parser)
    return try await db.fetch(from: path)
  }

  public func encode<T: Encodable>(_ value: T, documentName: String?) throws -> Data {
    try parser.encode(value, documentName: documentName)
  }

  public func fetchPage<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int?, pageToken: String?
  ) async throws -> FirestorePage<T> {
    let db = FirestoreDocument(config: config, parser: parser)
    return try await db.fetchPage(type, from: path, pageSize: pageSize, pageToken: pageToken)
  }

  public func batchGet(
    documents: [String],
    mask: FirestoreDocumentMask?
  ) async throws -> [FirestoreBatchGetResult] {
    let db = FirestoreDocument(config: config, parser: parser)
    return try await db.batchGet(documents: documents, mask: mask)
  }

  public func commit(
    writes: [FirestoreWrite],
    transaction: String?
  ) async throws -> FirestoreCommitResponse {
    let db = FirestoreDocument(config: config, parser: parser)
    return try await db.commit(writes: writes, transaction: transaction)
  }

  public func batchWrite(
    writes: [FirestoreWrite],
    labels: [String: String]?
  ) async throws -> FirestoreBatchWriteResponse {
    let db = FirestoreDocument(config: config, parser: parser)
    return try await db.batchWrite(writes: writes, labels: labels)
  }
}
