import Foundation
import FirestoreRestDocuments

public struct MockFirestoreClient: FirestoreClient {
  public var decodeHandler: @Sendable (Any.Type, String) async throws -> Any
  public var fetchHandler: @Sendable (String) async throws -> Data
  public var encodeHandler: @Sendable (Any, String?) throws -> Data
  public var fetchPageHandler: @Sendable (Any.Type, String, Int?, String?) async throws -> Any
  public var batchGetHandler: @Sendable ([String], FirestoreDocumentMask?) async throws -> [FirestoreBatchGetResult]
  public var commitHandler: @Sendable ([FirestoreWrite], String?) async throws -> FirestoreCommitResponse
  public var batchWriteHandler: @Sendable ([FirestoreWrite], [String: String]?) async throws -> FirestoreBatchWriteResponse

  public init(
    decodeHandler: @escaping @Sendable (Any.Type, String) async throws -> Any = { _, _ in
      throw FirestoreParsingError.decodingFailed("decode not stubbed")
    },
    fetchHandler: @escaping @Sendable (String) async throws -> Data = { _ in
      throw FirestoreParsingError.decodingFailed("fetch not stubbed")
    },
    encodeHandler: @escaping @Sendable (Any, String?) throws -> Data = { _, _ in
      throw FirestoreParsingError.encodingFailed("encode not stubbed")
    },
    fetchPageHandler: @escaping @Sendable (Any.Type, String, Int?, String?) async throws -> Any = { _, _, _, _ in
      throw FirestoreParsingError.decodingFailed("fetchPage not stubbed")
    },
    batchGetHandler: @escaping @Sendable ([String], FirestoreDocumentMask?) async throws -> [FirestoreBatchGetResult] = { _, _ in
      throw FirestoreParsingError.decodingFailed("batchGet not stubbed")
    },
    commitHandler: @escaping @Sendable ([FirestoreWrite], String?) async throws -> FirestoreCommitResponse = { _, _ in
      throw FirestoreParsingError.decodingFailed("commit not stubbed")
    },
    batchWriteHandler: @escaping @Sendable ([FirestoreWrite], [String: String]?) async throws -> FirestoreBatchWriteResponse = { _, _ in
      throw FirestoreParsingError.decodingFailed("batchWrite not stubbed")
    }
  ) {
    self.decodeHandler = decodeHandler
    self.fetchHandler = fetchHandler
    self.encodeHandler = encodeHandler
    self.fetchPageHandler = fetchPageHandler
    self.batchGetHandler = batchGetHandler
    self.commitHandler = commitHandler
    self.batchWriteHandler = batchWriteHandler
  }

  public func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T {
    try await decodeHandler(type, path) as! T
  }

  public func fetch(from path: String) async throws -> Data {
    try await fetchHandler(path)
  }

  public func encode<T: Encodable>(_ value: T, documentName: String?) throws -> Data {
    try encodeHandler(value, documentName)
  }

  public func fetchPage<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int?, pageToken: String?
  ) async throws -> FirestorePage<T> {
    try await fetchPageHandler(type, path, pageSize, pageToken) as! FirestorePage<T>
  }

  public func batchGet(
    documents: [String],
    mask: FirestoreDocumentMask?
  ) async throws -> [FirestoreBatchGetResult] {
    try await batchGetHandler(documents, mask)
  }

  public func commit(
    writes: [FirestoreWrite],
    transaction: String?
  ) async throws -> FirestoreCommitResponse {
    try await commitHandler(writes, transaction)
  }

  public func batchWrite(
    writes: [FirestoreWrite],
    labels: [String: String]?
  ) async throws -> FirestoreBatchWriteResponse {
    try await batchWriteHandler(writes, labels)
  }
}
