import Foundation

public struct FirestoreBatch {
  private var writes: [FirestoreWrite] = []

  public init() {}

  public var count: Int { writes.count }

  public mutating func create<T: Encodable & Sendable>(
    _ value: T, at documentPath: String,
    using parser: FirestoreDocumentParser = .init()
  ) throws {
    writes.append(try FirestoreWrite.create(value, at: documentPath, using: parser))
  }

  public mutating func update<T: Encodable & Sendable>(
    _ value: T, at documentPath: String,
    updateMask: [String]? = nil,
    using parser: FirestoreDocumentParser = .init()
  ) throws {
    writes.append(try FirestoreWrite.update(value, at: documentPath, updateMask: updateMask, using: parser))
  }

  public mutating func delete(at documentPath: String) {
    writes.append(.delete(at: documentPath))
  }

  public func commit(using db: FirestoreDocument) async throws -> FirestoreCommitResponse {
    try await db.commit(writes: writes)
  }

  public func batchWrite(
    using db: FirestoreDocument,
    labels: [String: String]? = nil
  ) async throws -> FirestoreBatchWriteResponse {
    try await db.batchWrite(writes: writes, labels: labels)
  }

  public func apply(to db: FirestoreDocument) async throws -> FirestoreCommitResponse {
    try await commit(using: db)
  }
}
