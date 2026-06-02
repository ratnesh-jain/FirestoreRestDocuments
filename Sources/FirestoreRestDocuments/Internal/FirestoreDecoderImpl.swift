import Foundation

final class _FirestoreDecoder: Decoder {
  let codingPath: [CodingKey]
  let userInfo: [CodingUserInfoKey: Any]
  let box: FirestoreValueBox

  init(value: FirestoreValue, codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey: Any] = [:]) {
    self.box = FirestoreValueBox(value)
    self.codingPath = codingPath
    if case .document(let name, _) = value {
      var info = userInfo
      info[.documentNameUserInfoKey] = name
      self.userInfo = info
    } else {
      self.userInfo = userInfo
    }
  }

  func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
    switch box.value {
    case .map(let dict):
      return KeyedDecodingContainer(FirestoreKeyedDecodingContainer<Key>(
        dict: dict, codingPath: codingPath, userInfo: userInfo
      ))
    case .document(let name, let fields):
      var info = userInfo
      info[.documentNameUserInfoKey] = name
      return KeyedDecodingContainer(FirestoreKeyedDecodingContainer<Key>(
        dict: fields, codingPath: codingPath, userInfo: info
      ))
    case .null:
      throw DecodingError.valueNotFound(
        [String: FirestoreValue].self,
        DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot get keyed decoding container -- found null value")
      )
    default:
      throw DecodingError.typeMismatch(
        [String: FirestoreValue].self,
        DecodingError.Context(codingPath: codingPath,
                              debugDescription: "Expected to decode a map but found \(box.value)")
      )
    }
  }

  func unkeyedContainer() throws -> UnkeyedDecodingContainer {
    switch box.value {
    case .array(let items):
      return FirestoreUnkeyedDecodingContainer(
        items: items, codingPath: codingPath, userInfo: userInfo
      )
    case .null:
      throw DecodingError.valueNotFound(
        [FirestoreValue].self,
        DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot get unkeyed decoding container -- found null value")
      )
    default:
      throw DecodingError.typeMismatch(
        [FirestoreValue].self,
        DecodingError.Context(codingPath: codingPath,
                              debugDescription: "Expected to decode an array but found \(box.value)")
      )
    }
  }

  func singleValueContainer() throws -> SingleValueDecodingContainer {
    let value: FirestoreValue
    if case .document(_, let fields) = box.value {
      value = .map(fields)
    } else {
      value = box.value
    }
    return FirestoreSingleValueDecodingContainer(
      value: value, codingPath: codingPath, userInfo: userInfo
    )
  }
}

final class FirestoreSingleValueDecodingContainer: SingleValueDecodingContainer {
  let codingPath: [CodingKey]
  let userInfo: [CodingUserInfoKey: Any]
  let value: FirestoreValue

  init(value: FirestoreValue, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
    self.value = value
    self.codingPath = codingPath
    self.userInfo = userInfo
  }

  func decodeNil() -> Bool {
    if case .null = value { return true }
    return false
  }

  func decode(_ type: Bool.Type) throws -> Bool {
    guard case .bool(let b) = value else {
      throw _typeMismatch(expected: Bool.self, actual: value)
    }
    return b
  }

  func decode(_ type: String.Type) throws -> String {
    switch value {
    case .string(let s):
      return s
    case .reference(let ref):
      return ref
    default:
      throw _typeMismatch(expected: String.self, actual: value)
    }
  }

  func decode(_ type: Double.Type) throws -> Double {
    switch value {
    case .double(let d):
      return d
    case .int(let i):
      return Double(i)
    default:
      throw _typeMismatch(expected: Double.self, actual: value)
    }
  }

  func decode(_ type: Float.Type) throws -> Float {
    switch value {
    case .double(let d):
      return Float(d)
    case .int(let i):
      return Float(i)
    default:
      throw _typeMismatch(expected: Float.self, actual: value)
    }
  }

  func decode(_ type: Int.Type) throws -> Int {
    guard case .int(let i) = value else {
      throw _typeMismatch(expected: Int.self, actual: value)
    }
    return Int(i)
  }

  func decode(_ type: Int8.Type) throws -> Int8 {
    guard case .int(let i) = value else { throw _typeMismatch(expected: Int8.self, actual: value) }
    return Int8(i)
  }

  func decode(_ type: Int16.Type) throws -> Int16 {
    guard case .int(let i) = value else { throw _typeMismatch(expected: Int16.self, actual: value) }
    return Int16(i)
  }

  func decode(_ type: Int32.Type) throws -> Int32 {
    guard case .int(let i) = value else { throw _typeMismatch(expected: Int32.self, actual: value) }
    return Int32(i)
  }

  func decode(_ type: Int64.Type) throws -> Int64 {
    guard case .int(let i) = value else { throw _typeMismatch(expected: Int64.self, actual: value) }
    return i
  }

  func decode(_ type: UInt.Type) throws -> UInt {
    guard case .int(let i) = value else { throw _typeMismatch(expected: UInt.self, actual: value) }
    return UInt(i)
  }

  func decode(_ type: UInt8.Type) throws -> UInt8 {
    guard case .int(let i) = value else { throw _typeMismatch(expected: UInt8.self, actual: value) }
    return UInt8(i)
  }

  func decode(_ type: UInt16.Type) throws -> UInt16 {
    guard case .int(let i) = value else { throw _typeMismatch(expected: UInt16.self, actual: value) }
    return UInt16(i)
  }

  func decode(_ type: UInt32.Type) throws -> UInt32 {
    guard case .int(let i) = value else { throw _typeMismatch(expected: UInt32.self, actual: value) }
    return UInt32(i)
  }

  func decode(_ type: UInt64.Type) throws -> UInt64 {
    guard case .int(let i) = value else { throw _typeMismatch(expected: UInt64.self, actual: value) }
    return UInt64(i)
  }

  func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
    if type == Date.self || type == NSDate.self {
      if case .timestamp(let date) = value {
        return date as! T
      }
      if case .string(let s) = value,
         let date = _iso8601WithFractionalSeconds().date(from: s) {
        return date as! T
      }
      if let date = _dateFromSecondsNanosMap(value) {
        return date as! T
      }
      throw _typeMismatch(expected: Date.self, actual: value)
    }
    if type == Data.self || type == NSData.self {
      if case .bytes(let data) = value {
        return data as! T
      }
      throw _typeMismatch(expected: Data.self, actual: value)
    }
    if type == FirestoreGeoPoint.self {
      if case .geoPoint(let lat, let lon) = value {
        return FirestoreGeoPoint(latitude: lat, longitude: lon) as! T
      }
      throw _typeMismatch(expected: FirestoreGeoPoint.self, actual: value)
    }
    if type == URL.self || type == NSURL.self {
      if case .string(let s) = value, let url = URL(string: s) {
        return url as! T
      }
      throw _typeMismatch(expected: URL.self, actual: value)
    }
    let decoder = _FirestoreDecoder(value: value, codingPath: codingPath, userInfo: userInfo)
    return try T(from: decoder)
  }

  private func _typeMismatch(expected: Any.Type, actual: FirestoreValue) -> DecodingError {
    return DecodingError.typeMismatch(
      expected,
      DecodingError.Context(codingPath: codingPath,
                            debugDescription: "Expected to decode \(expected), found \(actual)")
    )
  }
}

struct FirestoreKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
  let codingPath: [CodingKey]
  let userInfo: [CodingUserInfoKey: Any]
  let dict: [String: FirestoreValue]

  var allKeys: [Key] {
    dict.keys.compactMap { Key(stringValue: $0) }
  }

  init(dict: [String: FirestoreValue], codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
    self.dict = dict
    self.codingPath = codingPath
    self.userInfo = userInfo
  }

  func contains(_ key: Key) -> Bool {
    dict.keys.contains(key.stringValue)
  }

  func decodeNil(forKey key: Key) throws -> Bool {
    guard let value = dict[key.stringValue] else {
      throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key \(key)"))
    }
    if case .null = value { return true }
    return false
  }

  func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
    try value(for: key, type: type) { try $0.decode(Bool.self) }
  }

  func decode(_ type: String.Type, forKey key: Key) throws -> String {
    try value(for: key, type: type) { try $0.decode(String.self) }
  }

  func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
    try value(for: key, type: type) { try $0.decode(Double.self) }
  }

  func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
    try value(for: key, type: type) { try $0.decode(Float.self) }
  }

  func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
    try value(for: key, type: type) { try $0.decode(Int.self) }
  }

  func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
    try value(for: key, type: type) { try $0.decode(Int8.self) }
  }

  func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
    try value(for: key, type: type) { try $0.decode(Int16.self) }
  }

  func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
    try value(for: key, type: type) { try $0.decode(Int32.self) }
  }

  func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
    try value(for: key, type: type) { try $0.decode(Int64.self) }
  }

  func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
    try value(for: key, type: type) { try $0.decode(UInt.self) }
  }

  func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
    try value(for: key, type: type) { try $0.decode(UInt8.self) }
  }

  func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
    try value(for: key, type: type) { try $0.decode(UInt16.self) }
  }

  func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
    try value(for: key, type: type) { try $0.decode(UInt32.self) }
  }

  func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
    try value(for: key, type: type) { try $0.decode(UInt64.self) }
  }

  func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
    guard let fv = dict[key.stringValue] else {
      if let docIDType = T.self as? DocumentIDProtocol.Type {
        let docName = userInfo[CodingUserInfoKey.documentNameUserInfoKey] as? String
        return try docIDType.init(from: docName) as! T
      }
      throw DecodingError.keyNotFound(key, DecodingError.Context(
        codingPath: codingPath + [key],
        debugDescription: "No value associated with key \(key)"
      ))
    }
    if fv == .null, let OptionalType = T.self as? _OptionalProtocol.Type {
      return OptionalType._nil as! T
    }
    if type == Date.self || type == NSDate.self {
      if case .timestamp(let date) = fv {
        return date as! T
      }
      if let date = _dateFromSecondsNanosMap(fv) {
        return date as! T
      }
      throw DecodingError.typeMismatch(type, DecodingError.Context(
        codingPath: codingPath + [key],
        debugDescription: "Expected timestamp but found \(fv)"
      ))
    }
    if type == Data.self || type == NSData.self {
      if case .bytes(let data) = fv {
        return data as! T
      }
      throw DecodingError.typeMismatch(type, DecodingError.Context(
        codingPath: codingPath + [key],
        debugDescription: "Expected bytes but found \(fv)"
      ))
    }
    if type == FirestoreGeoPoint.self {
      if case .geoPoint(let lat, let lon) = fv {
        return FirestoreGeoPoint(latitude: lat, longitude: lon) as! T
      }
      throw DecodingError.typeMismatch(type, DecodingError.Context(
        codingPath: codingPath + [key],
        debugDescription: "Expected geoPoint but found \(fv)"
      ))
    }
    if type == URL.self || type == NSURL.self {
      if case .string(let s) = fv, let url = URL(string: s) {
        return url as! T
      }
      throw DecodingError.typeMismatch(type, DecodingError.Context(
        codingPath: codingPath + [key],
        debugDescription: "Expected URL string but found \(fv)"
      ))
    }
    let decoder = _FirestoreDecoder(value: fv, codingPath: codingPath + [key], userInfo: userInfo)
    return try T(from: decoder)
  }

  func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
    guard let fv = dict[key.stringValue] else {
      throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key \(key)"))
    }
    guard case .map(let nestedDict) = fv else {
      throw DecodingError.typeMismatch([String: FirestoreValue].self, DecodingError.Context(
        codingPath: codingPath + [key], debugDescription: "Expected map for nested container"
      ))
    }
    return KeyedDecodingContainer(FirestoreKeyedDecodingContainer<NestedKey>(
      dict: nestedDict, codingPath: codingPath + [key], userInfo: userInfo
    ))
  }

  func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
    guard let fv = dict[key.stringValue] else {
      throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath + [key], debugDescription: "No value associated with key \(key)"))
    }
    guard case .array(let items) = fv else {
      throw DecodingError.typeMismatch([FirestoreValue].self, DecodingError.Context(
        codingPath: codingPath + [key], debugDescription: "Expected array for nested unkeyed container"
      ))
    }
    return FirestoreUnkeyedDecodingContainer(items: items, codingPath: codingPath + [key], userInfo: userInfo)
  }

  func superDecoder() throws -> Decoder {
    let fv = dict["super"] ?? .map([:])
    return _FirestoreDecoder(value: fv, codingPath: codingPath, userInfo: userInfo)
  }

  func superDecoder(forKey key: Key) throws -> Decoder {
    let fv = dict[key.stringValue] ?? .map([:])
    return _FirestoreDecoder(value: fv, codingPath: codingPath + [key], userInfo: userInfo)
  }

  private func value<T>(for key: Key, type: T.Type, decode: (SingleValueDecodingContainer) throws -> T) throws -> T {
    guard let fv = dict[key.stringValue] else {
      throw DecodingError.keyNotFound(key, DecodingError.Context(
        codingPath: codingPath + [key], debugDescription: "No value associated with key \(key)"
      ))
    }
    let container = FirestoreSingleValueDecodingContainer(value: fv, codingPath: codingPath + [key], userInfo: userInfo)
    return try decode(container)
  }
}

struct FirestoreUnkeyedDecodingContainer: UnkeyedDecodingContainer {
  let codingPath: [CodingKey]
  let userInfo: [CodingUserInfoKey: Any]
  let items: [FirestoreValue]
  var currentIndex: Int = 0

  var count: Int? { items.count }
  var isAtEnd: Bool { currentIndex >= items.count }

  init(items: [FirestoreValue], codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
    self.items = items
    self.codingPath = codingPath
    self.userInfo = userInfo
  }

  mutating func decodeNil() throws -> Bool {
    if isAtEnd { throw _overflow() }
    if case .null = items[currentIndex] {
      currentIndex += 1
      return true
    }
    return false
  }

  mutating func decode(_ type: Bool.Type) throws -> Bool { try _decode { try $0.decode(Bool.self) } }
  mutating func decode(_ type: String.Type) throws -> String { try _decode { try $0.decode(String.self) } }
  mutating func decode(_ type: Double.Type) throws -> Double { try _decode { try $0.decode(Double.self) } }
  mutating func decode(_ type: Float.Type) throws -> Float { try _decode { try $0.decode(Float.self) } }
  mutating func decode(_ type: Int.Type) throws -> Int { try _decode { try $0.decode(Int.self) } }
  mutating func decode(_ type: Int8.Type) throws -> Int8 { try _decode { try $0.decode(Int8.self) } }
  mutating func decode(_ type: Int16.Type) throws -> Int16 { try _decode { try $0.decode(Int16.self) } }
  mutating func decode(_ type: Int32.Type) throws -> Int32 { try _decode { try $0.decode(Int32.self) } }
  mutating func decode(_ type: Int64.Type) throws -> Int64 { try _decode { try $0.decode(Int64.self) } }
  mutating func decode(_ type: UInt.Type) throws -> UInt { try _decode { try $0.decode(UInt.self) } }
  mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try _decode { try $0.decode(UInt8.self) } }
  mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try _decode { try $0.decode(UInt16.self) } }
  mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try _decode { try $0.decode(UInt32.self) } }
  mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try _decode { try $0.decode(UInt64.self) } }

  mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
    guard !isAtEnd else { throw _overflow() }
    let value = items[currentIndex]
    currentIndex += 1
    let decoder = _FirestoreDecoder(value: value, codingPath: codingPath + [_IndexKey(intValue: currentIndex - 1)], userInfo: userInfo)
    return try T(from: decoder)
  }

  mutating func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
    let decoder = try _decoderForNext()
    return try decoder.container(keyedBy: type)
  }

  mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
    let decoder = try _decoderForNext()
    return try decoder.unkeyedContainer()
  }

  mutating func superDecoder() throws -> Decoder {
    try _decoderForNext()
  }

  private mutating func _decode<T>(_ decode: (SingleValueDecodingContainer) throws -> T) throws -> T {
    guard !isAtEnd else { throw _overflow() }
    let fv = items[currentIndex]
    currentIndex += 1
    let container = FirestoreSingleValueDecodingContainer(value: fv, codingPath: codingPath + [_IndexKey(intValue: currentIndex - 1)], userInfo: userInfo)
    return try decode(container)
  }

  private mutating func _decoderForNext() throws -> Decoder {
    guard !isAtEnd else { throw _overflow() }
    let fv = items[currentIndex]
    currentIndex += 1
    return _FirestoreDecoder(value: fv, codingPath: codingPath + [_IndexKey(intValue: currentIndex - 1)], userInfo: userInfo)
  }

  private func _overflow() -> DecodingError {
    DecodingError.valueNotFound(Any.self, DecodingError.Context(
      codingPath: codingPath, debugDescription: "Unkeyed container is at end"
    ))
  }
}

struct _IndexKey: CodingKey {
  let intValue: Int?
  let stringValue: String

  init(intValue: Int) {
    self.intValue = intValue
    self.stringValue = "Index \(intValue)"
  }

  init?(stringValue: String) { nil }
}

func _iso8601WithFractionalSeconds() -> ISO8601DateFormatter {
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return f
}

func _dateFromSecondsNanosMap(_ value: FirestoreValue) -> Date? {
  guard case .map(let dict) = value else { return nil }
  let seconds: Int64
  switch dict["seconds"] {
  case .int(let s): seconds = s
  case .string(let s) where Int64(s) != nil: seconds = Int64(s)!
  default: return nil
  }
  let nanos: Int64
  switch dict["nanoseconds"] {
  case .int(let n): nanos = n
  case .string(let n) where Int64(n) != nil: nanos = Int64(n)!
  default: nanos = 0
  }
  return Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanos) / 1_000_000_000)
}

protocol _OptionalProtocol {
  static var _nil: Self { get }
}

extension Optional: _OptionalProtocol {
  static var _nil: Self { nil }
}
