import Foundation

func parseFirestoreValue(from json: Any) throws -> FirestoreValue {
  guard let dict = json as? [String: Any] else {
    throw FirestoreParsingError.invalidValueFormat("Expected a dictionary for Firestore value wrapper, got \(type(of: json))")
  }

  if dict.keys.contains("nullValue") {
    return .null
  }

  if let val = dict["booleanValue"] {
    if let str = val as? String {
      return .bool(str == "true")
    }
    if let b = val as? Bool {
      return .bool(b)
    }
  }

  if let val = dict["integerValue"] {
    if let str = val as? String {
      if let i = Int64(str) {
        return .int(i)
      }
      throw FirestoreParsingError.invalidValueFormat("Invalid integerValue: \(str)")
    }
    if let n = val as? NSNumber {
      return .int(n.int64Value)
    }
  }

  if let val = dict["doubleValue"] {
    if let str = val as? String {
      if let d = Double(str) {
        return .double(d)
      }
      throw FirestoreParsingError.invalidValueFormat("Invalid doubleValue: \(str)")
    }
    if let n = val as? NSNumber {
      return .double(n.doubleValue)
    }
  }

  if let val = dict["stringValue"] as? String {
    return .string(val)
  }

  if let val = dict["timestampValue"] {
    if let string = val as? String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: string) {
        return .timestamp(date)
      }
      formatter.formatOptions = [.withInternetDateTime]
      if let date = formatter.date(from: string) {
        return .timestamp(date)
      }
      throw FirestoreParsingError.invalidValueFormat("Invalid timestampValue: \(string)")
    }
    if let obj = val as? [String: Any] {
      let seconds: TimeInterval
      if let secStr = obj["seconds"] as? String, let sec = Double(secStr) {
        seconds = sec
      } else if let sec = obj["seconds"] as? Double {
        seconds = sec
      } else {
        throw FirestoreParsingError.invalidValueFormat("Missing or invalid 'seconds' in timestampValue: \(obj)")
      }
      let nanos: Double
      if let nanoStr = (obj["nanoseconds"] as? String) ?? (obj["nanos"] as? String),
         let nano = Double(nanoStr) {
        nanos = nano
      } else if let nano = (obj["nanoseconds"] as? Double) ?? (obj["nanos"] as? Double) {
        nanos = nano
      } else {
        nanos = 0
      }
      return .timestamp(Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000))
    }
  }

  if let val = dict["referenceValue"] as? String {
    return .reference(val)
  }

  if let val = dict["geoPointValue"] as? [String: Any] {
    guard let lat = val["latitude"] as? Double, let lon = val["longitude"] as? Double else {
      throw FirestoreParsingError.invalidValueFormat("Invalid geoPointValue: \(val)")
    }
    return .geoPoint(latitude: lat, longitude: lon)
  }

  if let val = dict["bytesValue"] as? String {
    guard let data = Data(base64Encoded: val) else {
      throw FirestoreParsingError.invalidValueFormat("Invalid bytesValue (not valid base64): \(val)")
    }
    return .bytes(data)
  }

  if let val = dict["arrayValue"] as? [String: Any] {
    let values = val["values"] as? [Any] ?? []
      let items = try values.map { try parseFirestoreValue(from: $0) }
    return .array(items)
  }

  if let val = dict["mapValue"] as? [String: Any] {
    let fields = val["fields"] as? [String: Any] ?? [:]
    var result: [String: FirestoreValue] = [:]
    for (key, value) in fields {
      result[key] = try parseFirestoreValue(from: value)
    }
    return .map(result)
  }

  if dict.isEmpty {
    return .map([:])
  }

  throw FirestoreParsingError.unknownValueType("Unknown Firestore value type in: \(dict)")
}

func firestoreValueToJSONCompatible(_ value: FirestoreValue) -> Any {
  switch value {
  case .null:
    return NSNull()
  case .bool(let b):
    return ["booleanValue": b ? "true" : "false"]
  case .int(let i):
    return ["integerValue": String(i)]
  case .double(let d):
    if d.isInfinite || d.isNaN {
      return ["doubleValue": String(d)]
    }
    return ["doubleValue": d]
  case .string(let s):
    return ["stringValue": s]
  case .bytes(let data):
    return ["bytesValue": data.base64EncodedString()]
  case .timestamp(let date):
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return ["timestampValue": formatter.string(from: date)]
  case .geoPoint(let lat, let lon):
    return ["geoPointValue": ["latitude": lat, "longitude": lon]]
  case .reference(let ref):
    return ["referenceValue": ref]
  case .array(let items):
    let jsonValues = items.map { firestoreValueToJSONCompatible($0) }
    return ["arrayValue": ["values": jsonValues]]
  case .map(let dict):
    var fields: [String: Any] = [:]
    for (key, val) in dict {
      fields[key] = firestoreValueToJSONCompatible(val)
    }
    return ["mapValue": ["fields": fields]]
  case .document(_, let fields):
    var result: [String: Any] = [:]
    for (key, val) in fields {
      result[key] = firestoreValueToJSONCompatible(val)
    }
    return ["mapValue": ["fields": result]]
  }
}
