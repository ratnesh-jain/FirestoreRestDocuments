import Foundation

extension CodingUserInfoKey {
  static let documentNameUserInfoKey = CodingUserInfoKey(rawValue: "DocumentNameUserInfoKey")!
}

public protocol DocumentIDWrappable {
  static func wrap(_ documentName: String) throws -> Self
}

extension String: DocumentIDWrappable {
  public static func wrap(_ documentName: String) throws -> Self {
    return documentName
  }
}

protocol DocumentIDProtocol {
  init(from documentName: String?) throws
}

@propertyWrapper
public struct DocumentID<Value: DocumentIDWrappable & Codable>: Codable {
  private var value: Value?

  public init(wrappedValue value: Value?) {
    self.value = value
  }

  public var wrappedValue: Value? {
    get { value }
    set { value = newValue }
  }

  public init(from decoder: Decoder) throws {
    guard let documentName = decoder.userInfo[CodingUserInfoKey.documentNameUserInfoKey] as? String else {
      throw FirestoreParsingError.decodingFailed(
        "Could not find document name for @DocumentID. Use DocumentInfo to provide it."
      )
    }
    value = try Value.wrap(documentName)
  }

  public func encode(to encoder: Encoder) throws {
    // DocumentID is ignored on encode (like the Firebase SDK behavior)
  }
}

extension DocumentID: DocumentIDProtocol {
  init(from documentName: String?) throws {
    if let documentName {
      value = try Value.wrap(documentName)
    } else {
      value = nil
    }
  }
}

extension DocumentID: Equatable where Value: Equatable {}
extension DocumentID: Hashable where Value: Hashable {}
extension DocumentID: Sendable where Value: Sendable {}

public protocol ServerTimestampWrappable {
  static func wrap(_ date: Date) throws -> Self
}

extension Date: ServerTimestampWrappable {
  public static func wrap(_ date: Date) throws -> Self { date }
}

@propertyWrapper
public struct ServerTimestamp<Value>: Codable where Value: ServerTimestampWrappable & Codable {
  private var value: Value?

  public init(wrappedValue value: Value?) {
    self.value = value
  }

  public var wrappedValue: Value? {
    get { value }
    set { value = newValue }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = nil
    } else {
      let date = try container.decode(Date.self)
      value = try Value.wrap(date)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    if let value {
      if let date = value as? Date {
        try container.encode(date)
      } else {
        try container.encode(value)
      }
    } else {
      try container.encodeNil()
    }
  }
}

extension ServerTimestamp: Equatable where Value: Equatable {}
extension ServerTimestamp: Hashable where Value: Hashable {}

@propertyWrapper
public struct ExplicitNull<Value> {
  private var value: Value?

  public init(wrappedValue value: Value?) {
    self.value = value
  }

  public var wrappedValue: Value? {
    get { value }
    set { value = newValue }
  }
}

extension ExplicitNull: Equatable where Value: Equatable {}
extension ExplicitNull: Hashable where Value: Hashable {}

extension ExplicitNull: Encodable where Value: Encodable {
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    if let value {
      try container.encode(value)
    } else {
      try container.encodeNil()
    }
  }
}

extension ExplicitNull: Decodable where Value: Decodable {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = nil
    } else {
      value = try container.decode(Value.self)
    }
  }
}
