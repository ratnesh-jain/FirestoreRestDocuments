import Foundation
import Logging

public struct DocumentInfo: Sendable {
  public let name: String?

  public init(name: String?) {
    self.name = name
  }

  public init(path: String) {
    self.name = path
  }
}

// MARK: - Strategies

public enum DateDecodingStrategy: Sendable {
  case iso8601
  case custom(@Sendable (Decoder) throws -> Date)
}

public enum DateEncodingStrategy: Sendable {
  case iso8601
  case custom(@Sendable (Date, Encoder) throws -> Void)
}

public enum DataDecodingStrategy: Sendable {
  case base64
  case custom(@Sendable (Decoder) throws -> Data)
}

public enum DataEncodingStrategy: Sendable {
  case base64
  case custom(@Sendable (Data, Encoder) throws -> Void)
}

public enum KeyDecodingStrategy: Sendable {
  case useDefaultKeys
  case convertFromSnakeCase
  case custom(@Sendable ([CodingKey]) -> CodingKey)
}

public enum KeyEncodingStrategy: Sendable {
  case useDefaultKeys
  case convertToSnakeCase
  case custom(@Sendable ([CodingKey]) -> CodingKey)
}

// MARK: - Parser

public struct FirestoreDocumentParser: Sendable {
  public var dateDecodingStrategy: DateDecodingStrategy
  public var dateEncodingStrategy: DateEncodingStrategy
  public var dataDecodingStrategy: DataDecodingStrategy
  public var dataEncodingStrategy: DataEncodingStrategy
  public var keyDecodingStrategy: KeyDecodingStrategy
  public var keyEncodingStrategy: KeyEncodingStrategy

  public init(
    dateDecodingStrategy: DateDecodingStrategy = .iso8601,
    dateEncodingStrategy: DateEncodingStrategy = .iso8601,
    dataDecodingStrategy: DataDecodingStrategy = .base64,
    dataEncodingStrategy: DataEncodingStrategy = .base64,
    keyDecodingStrategy: KeyDecodingStrategy = .useDefaultKeys,
    keyEncodingStrategy: KeyEncodingStrategy = .useDefaultKeys
  ) {
    self.dateDecodingStrategy = dateDecodingStrategy
    self.dateEncodingStrategy = dateEncodingStrategy
    self.dataDecodingStrategy = dataDecodingStrategy
    self.dataEncodingStrategy = dataEncodingStrategy
    self.keyDecodingStrategy = keyDecodingStrategy
    self.keyEncodingStrategy = keyEncodingStrategy
  }

  public func decode<T: Decodable>(
    _ type: T.Type,
    from data: Data,
    documentInfo: DocumentInfo? = nil
  ) throws -> T {
    Logger.firestoreRestDocuments.trace("Decoding \(T.self) from data (\(data.count) bytes)")
    do {
      let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
      return try decode(type, from: json, documentInfo: documentInfo)
    } catch {
      Logger.firestoreRestDocuments.error("Decoding \(T.self) failed: \(error.localizedDescription)")
      throw error
    }
  }

  public func decode<T: Decodable>(
    _ type: T.Type,
    from json: Any,
    documentInfo: DocumentInfo? = nil
  ) throws -> T {
    Logger.firestoreRestDocuments.trace("Decoding \(T.self) from JSON")
    let rootValue = try normalizeJSON(json)

    var userInfo: [CodingUserInfoKey: Any] = [:]
    userInfo[.documentNameUserInfoKey] = documentInfo?.name ?? extractDocumentName(from: json)

    let decoder = _FirestoreDecoder(value: rootValue, userInfo: userInfo)
    return try T(from: decoder)
  }

  private func normalizeJSON(_ json: Any) throws -> FirestoreValue {
    if let array = json as? [Any] {
      let items = try array.map { element -> FirestoreValue in
        if let dict = element as? [String: Any], let fields = dict["fields"] as? [String: Any] {
          let parsed = try fields.mapValues { try parseFirestoreValue(from: $0) }
          if let name = dict["name"] as? String {
            return .document(name: name, fields: parsed)
          }
          return .map(parsed)
        }
        return try parseFirestoreValue(from: element)
      }
      return .array(items)
    }

    if let dict = json as? [String: Any] {
      if dict.isEmpty {
        return .array([])
      }

      if let fields = dict["fields"] as? [String: Any] {
        let parsed = try fields.mapValues { try parseFirestoreValue(from: $0) }
        if let name = dict["name"] as? String {
          return .document(name: name, fields: parsed)
        }
        return .map(parsed)
      }

      if let documents = dict["documents"] as? [[String: Any]] {
        let items = try documents.map { doc -> FirestoreValue in
          let fields = doc["fields"] as? [String: Any] ?? [:]
          let parsed = try fields.mapValues { try parseFirestoreValue(from: $0) }
          if let name = doc["name"] as? String {
            return .document(name: name, fields: parsed)
          }
          return .map(parsed)
        }
        return .array(items)
      }

      if let documentResults = dict["documentResults"] as? [[String: Any]] {
        let items = try documentResults.compactMap { result -> FirestoreValue? in
          guard let doc = result["document"] as? [String: Any],
                let fields = doc["fields"] as? [String: Any] else {
            return nil
          }
          let parsed = try fields.mapValues { try parseFirestoreValue(from: $0) }
          if let name = doc["name"] as? String {
            return .document(name: name, fields: parsed)
          }
          return .map(parsed)
        }
        return .array(items)
      }

      if let value = dict["value"] as? [String: Any] {
        return try parseFirestoreValue(from: value)
      }

      return try parseFirestoreValue(from: json)
    }

    return try parseFirestoreValue(from: json)
  }

  public func decodePage<T: Decodable>(
    _ type: T.Type,
    from data: Data
  ) throws -> FirestorePage<T> {
    Logger.firestoreRestDocuments.trace("Decoding page of \(T.self) from data (\(data.count) bytes)")
    let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return try decodePage(type, from: json)
  }

  public func decodePage<T: Decodable>(
    _ type: T.Type,
    from json: Any
  ) throws -> FirestorePage<T> {
    Logger.firestoreRestDocuments.trace("Decoding page of \(T.self) from JSON")
    guard let dict = json as? [String: Any] else {
      throw FirestoreParsingError.decodingFailed("Expected a JSON object for page response")
    }
    let nextPageToken = dict["nextPageToken"] as? String
    let documents = dict["documents"] as? [[String: Any]] ?? []
    let items = try documents.map { try decode(type, from: $0) }
    return FirestorePage(items: items, nextPageToken: nextPageToken)
  }

  public func encode<T: Encodable>(
    _ value: T,
    documentName: String? = nil
  ) throws -> Data {
    Logger.firestoreRestDocuments.trace("Encoding \(T.self) (documentName: \(documentName ?? "nil"))")
    let encoder = _FirestoreEncoder()
    try value.encode(to: encoder)
    let encoded = encoder.encodedValue

    guard case .map(let fields) = encoded else {
      Logger.firestoreRestDocuments.error("Top-level encoded value must be a map")
      throw FirestoreParsingError.encodingFailed("Top-level encoded value must be a map")
    }

    var document: [String: Any] = [:]
    if let name = documentName {
      document["name"] = name
    }
    var jsonFields: [String: Any] = [:]
    for (key, val) in fields {
      jsonFields[key] = firestoreValueToJSONCompatible(val)
    }
    document["fields"] = jsonFields

    Logger.firestoreRestDocuments.trace("Encoded \(T.self) to \(jsonFields.count) fields")
    return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
  }

  public func encodeFields<T: Encodable>(_ value: T) throws -> Data {
    Logger.firestoreRestDocuments.trace("Encoding fields for \(T.self)")
    let encoder = _FirestoreEncoder()
    try value.encode(to: encoder)
    let encoded = encoder.encodedValue

    guard case .map(let fields) = encoded else {
      Logger.firestoreRestDocuments.error("Top-level encoded value must be a map")
      throw FirestoreParsingError.encodingFailed("Top-level encoded value must be a map")
    }

    var jsonFields: [String: Any] = [:]
    for (key, val) in fields {
      jsonFields[key] = firestoreValueToJSONCompatible(val)
    }

    return try JSONSerialization.data(withJSONObject: jsonFields, options: [.sortedKeys])
  }

  public func encodeAsFieldsDictionary<T: Encodable>(_ value: T) throws -> [String: Any] {
    Logger.firestoreRestDocuments.trace("Encoding fields dictionary for \(T.self)")
    let encoder = _FirestoreEncoder()
    try value.encode(to: encoder)
    let encoded = encoder.encodedValue

    guard case .map(let fields) = encoded else {
      Logger.firestoreRestDocuments.error("Top-level encoded value must be a map")
      throw FirestoreParsingError.encodingFailed("Top-level encoded value must be a map")
    }

    var result: [String: Any] = [:]
    for (key, val) in fields {
      result[key] = firestoreValueToJSONCompatible(val)
    }
    return result
  }

  private func extractDocumentName(from json: Any) -> String? {
    (json as? [String: Any])?["name"] as? String
  }
}
