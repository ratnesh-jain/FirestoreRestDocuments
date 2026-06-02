import Foundation

final class _FirestoreEncoder: Encoder {
  let codingPath: [CodingKey]
  let userInfo: [CodingUserInfoKey: Any]
  var storage: FirestoreEncodingStorage

  init(codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey: Any] = [:]) {
    self.codingPath = codingPath
    self.userInfo = userInfo
    self.storage = FirestoreEncodingStorage()
  }

  func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
    let container = FirestoreKeyedEncodingContainer<Key>(
      referencing: self, codingPath: codingPath
    )
    return KeyedEncodingContainer(container)
  }

  func unkeyedContainer() -> UnkeyedEncodingContainer {
    FirestoreUnkeyedEncodingContainer(referencing: self, codingPath: codingPath)
  }

  func singleValueContainer() -> SingleValueEncodingContainer {
    FirestoreSingleValueEncodingContainer(referencing: self, codingPath: codingPath)
  }

  var encodedValue: FirestoreValue {
    storage.value
  }
}

final class FirestoreEncodingStorage {
  var value: FirestoreValue = .null
}

final class FirestoreSingleValueEncodingContainer: SingleValueEncodingContainer {
  let codingPath: [CodingKey]
  let encoder: _FirestoreEncoder

  init(referencing encoder: _FirestoreEncoder, codingPath: [CodingKey]) {
    self.encoder = encoder
    self.codingPath = codingPath
  }

  func encodeNil() throws { encoder.storage.value = .null }
  func encode(_ value: Bool) throws { encoder.storage.value = .bool(value) }
  func encode(_ value: String) throws { encoder.storage.value = .string(value) }
  func encode(_ value: Double) throws { encoder.storage.value = .double(value) }
  func encode(_ value: Float) throws { encoder.storage.value = .double(Double(value)) }

  func encode(_ value: Int) throws { encoder.storage.value = .int(Int64(value)) }
  func encode(_ value: Int8) throws { encoder.storage.value = .int(Int64(value)) }
  func encode(_ value: Int16) throws { encoder.storage.value = .int(Int64(value)) }
  func encode(_ value: Int32) throws { encoder.storage.value = .int(Int64(value)) }
  func encode(_ value: Int64) throws { encoder.storage.value = .int(value) }

  func encode(_ value: UInt) throws { encoder.storage.value = .int(Int64(value)) }
  func encode(_ value: UInt8) throws { encoder.storage.value = .int(Int64(value)) }
  func encode(_ value: UInt16) throws { encoder.storage.value = .int(Int64(value)) }
  func encode(_ value: UInt32) throws { encoder.storage.value = .int(Int64(value)) }
  func encode(_ value: UInt64) throws { encoder.storage.value = .int(Int64(value)) }

  func encode<T>(_ value: T) throws where T: Encodable {
    if let date = value as? Date {
      encoder.storage.value = .timestamp(date)
      return
    }
    if let data = value as? Data {
      encoder.storage.value = .bytes(data)
      return
    }
    let nestedEncoder = _FirestoreEncoder(codingPath: codingPath, userInfo: encoder.userInfo)
    try value.encode(to: nestedEncoder)
    encoder.storage.value = nestedEncoder.encodedValue
  }
}

final class FirestoreKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
  let codingPath: [CodingKey]
  let encoder: _FirestoreEncoder
  var dict: [String: FirestoreValue] = [:]

  init(referencing encoder: _FirestoreEncoder, codingPath: [CodingKey]) {
    self.encoder = encoder
    self.codingPath = codingPath
  }

  func encodeNil(forKey key: Key) throws { dict[key.stringValue] = .null }
  func encode(_ value: Bool, forKey key: Key) throws { dict[key.stringValue] = .bool(value) }
  func encode(_ value: String, forKey key: Key) throws { dict[key.stringValue] = .string(value) }
  func encode(_ value: Double, forKey key: Key) throws { dict[key.stringValue] = .double(value) }
  func encode(_ value: Float, forKey key: Key) throws { dict[key.stringValue] = .double(Double(value)) }
  func encode(_ value: Int, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }
  func encode(_ value: Int8, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }
  func encode(_ value: Int16, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }
  func encode(_ value: Int32, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }
  func encode(_ value: Int64, forKey key: Key) throws { dict[key.stringValue] = .int(value) }
  func encode(_ value: UInt, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }
  func encode(_ value: UInt8, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }
  func encode(_ value: UInt16, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }
  func encode(_ value: UInt32, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }
  func encode(_ value: UInt64, forKey key: Key) throws { dict[key.stringValue] = .int(Int64(value)) }

  func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
    if let date = value as? Date {
      dict[key.stringValue] = .timestamp(date)
      return
    }
    if let data = value as? Data {
      dict[key.stringValue] = .bytes(data)
      return
    }
    let nestedEncoder = _FirestoreEncoder(codingPath: codingPath + [key], userInfo: encoder.userInfo)
    try value.encode(to: nestedEncoder)
    dict[key.stringValue] = nestedEncoder.encodedValue
  }

  func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
    let nestedEncoder = _FirestoreEncoder(codingPath: codingPath + [key], userInfo: encoder.userInfo)
    let container = FirestoreKeyedEncodingContainer<NestedKey>(referencing: nestedEncoder, codingPath: codingPath + [key])
    dict[key.stringValue] = .map([:])
    nestedEncoder.storage.value = .map(container.dict)
    return KeyedEncodingContainer(container)
  }

  func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
    let nestedEncoder = _FirestoreEncoder(codingPath: codingPath + [key], userInfo: encoder.userInfo)
    let container = FirestoreUnkeyedEncodingContainer(referencing: nestedEncoder, codingPath: codingPath + [key])
    dict[key.stringValue] = .array([])
    nestedEncoder.storage.value = .array(container.items)
    return container
  }

  func superEncoder() -> Encoder {
    _FirestoreEncoder(codingPath: codingPath, userInfo: encoder.userInfo)
  }

  func superEncoder(forKey key: Key) -> Encoder {
    _FirestoreEncoder(codingPath: codingPath + [key], userInfo: encoder.userInfo)
  }

  deinit {
    encoder.storage.value = .map(dict)
  }
}

final class FirestoreUnkeyedEncodingContainer: UnkeyedEncodingContainer {
  let codingPath: [CodingKey]
  let encoder: _FirestoreEncoder
  var items: [FirestoreValue] = []
  var count: Int { items.count }

  init(referencing encoder: _FirestoreEncoder, codingPath: [CodingKey]) {
    self.encoder = encoder
    self.codingPath = codingPath
  }

  func encodeNil() throws { items.append(.null) }
  func encode(_ value: Bool) throws { items.append(.bool(value)) }
  func encode(_ value: String) throws { items.append(.string(value)) }
  func encode(_ value: Double) throws { items.append(.double(value)) }
  func encode(_ value: Float) throws { items.append(.double(Double(value))) }
  func encode(_ value: Int) throws { items.append(.int(Int64(value))) }
  func encode(_ value: Int8) throws { items.append(.int(Int64(value))) }
  func encode(_ value: Int16) throws { items.append(.int(Int64(value))) }
  func encode(_ value: Int32) throws { items.append(.int(Int64(value))) }
  func encode(_ value: Int64) throws { items.append(.int(value)) }
  func encode(_ value: UInt) throws { items.append(.int(Int64(value))) }
  func encode(_ value: UInt8) throws { items.append(.int(Int64(value))) }
  func encode(_ value: UInt16) throws { items.append(.int(Int64(value))) }
  func encode(_ value: UInt32) throws { items.append(.int(Int64(value))) }
  func encode(_ value: UInt64) throws { items.append(.int(Int64(value))) }

  func encode<T>(_ value: T) throws where T: Encodable {
    if let date = value as? Date {
      items.append(.timestamp(date))
      return
    }
    if let data = value as? Data {
      items.append(.bytes(data))
      return
    }
    let nestedEncoder = _FirestoreEncoder(codingPath: codingPath, userInfo: encoder.userInfo)
    try value.encode(to: nestedEncoder)
    items.append(nestedEncoder.encodedValue)
  }

  func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
    let nestedEncoder = _FirestoreEncoder(codingPath: codingPath, userInfo: encoder.userInfo)
    let container = FirestoreKeyedEncodingContainer<NestedKey>(referencing: nestedEncoder, codingPath: codingPath)
    items.append(.map([:]))
    nestedEncoder.storage.value = .map(container.dict)
    return KeyedEncodingContainer(container)
  }

  func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
    let nestedEncoder = _FirestoreEncoder(codingPath: codingPath, userInfo: encoder.userInfo)
    let container = FirestoreUnkeyedEncodingContainer(referencing: nestedEncoder, codingPath: codingPath)
    items.append(.array([]))
    nestedEncoder.storage.value = .array(container.items)
    return container
  }

  func superEncoder() -> Encoder {
    _FirestoreEncoder(codingPath: codingPath, userInfo: encoder.userInfo)
  }

  deinit {
    encoder.storage.value = .array(items)
  }
}
