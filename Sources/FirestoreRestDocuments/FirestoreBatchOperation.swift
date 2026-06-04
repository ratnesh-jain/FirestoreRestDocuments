import Foundation

// MARK: - BatchGet

public struct FirestoreBatchFoundDocument: Sendable {
  public let name: String
  public let fields: [String: FirestoreValue]
  public let createTime: String?
  public let updateTime: String?
}

public enum FirestoreBatchGetResult: Sendable {
  case found(FirestoreBatchFoundDocument)
  case missing(String)

  public var isFound: Bool {
    if case .found = self { true } else { false }
  }

  public var isMissing: Bool { !isFound }

  public var documentName: String? {
    switch self {
    case .found(let doc): return doc.name
    case .missing: return nil
    }
  }
}

// MARK: - Write

public struct FirestoreWrite: Sendable {
  public enum Storage: Sendable {
    case create(fieldsData: Data)
    case update(fieldsData: Data, updateMask: [String]?, exists: Bool?)
    case delete
  }

  public let documentPath: String
  public let storage: Storage

  public init(documentPath: String, storage: Storage) {
    self.documentPath = documentPath
    self.storage = storage
  }
}

extension FirestoreWrite {
  public static func create<T: Encodable & Sendable>(
    _ value: T, at documentPath: String,
    using parser: FirestoreDocumentParser = .init()
  ) throws -> FirestoreWrite {
    let body = try parser.encodeFields(value)
    return FirestoreWrite(documentPath: documentPath, storage: .create(fieldsData: body))
  }

  public static func update<T: Encodable & Sendable>(
    _ value: T, at documentPath: String,
    updateMask: [String]? = nil, exists: Bool? = nil,
    using parser: FirestoreDocumentParser = .init()
  ) throws -> FirestoreWrite {
    let body = try parser.encodeFields(value)
    return FirestoreWrite(documentPath: documentPath, storage: .update(fieldsData: body, updateMask: updateMask, exists: exists))
  }

  public static func delete(at documentPath: String) -> FirestoreWrite {
    FirestoreWrite(documentPath: documentPath, storage: .delete)
  }
}

// MARK: - Document Mask

public struct FirestoreDocumentMask: Codable, Sendable {
  public var fieldPaths: [String]
  public init(fieldPaths: [String]) { self.fieldPaths = fieldPaths }
}

// MARK: - Commit Response

public struct FirestoreCommitResponse: Codable, Sendable {
  public let writeResults: [FirestoreWriteResultEntry]
  public let commitTime: String
}

// MARK: - BatchWrite Response

public struct FirestoreBatchWriteResponse: Codable, Sendable {
  public let writeResults: [FirestoreWriteResultEntry]
  public let status: [FirestoreStatus]?
}

public struct FirestoreStatus: Codable, Sendable {
  public let code: Int?
  public let message: String?
}
