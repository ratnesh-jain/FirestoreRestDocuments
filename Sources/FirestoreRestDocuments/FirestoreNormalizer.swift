import Foundation
import Logging

/// Unwraps Firestore REST API's typed value format into flat JSON,
/// so standard `JSONDecoder` can decode it directly.
///
/// Firestore REST returns values wrapped with type annotations:
/// ```
/// {"name": {"stringValue": "Alice"}, "age": {"integerValue": "30"}}
/// ```
///
/// Normalizer converts this to plain JSON:
/// ```
/// {"name": "Alice", "age": 30}
/// ```
public struct FirestoreNormalizer {

  /// Normalize Firestore REST JSON data to flat JSON data.
  public static func normalize(_ data: Data) throws -> Data {
    Logger.firestoreRestDocuments.trace("Normalizing \(data.count) bytes of Firestore JSON")
    let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    let result = try normalize(json)
    Logger.firestoreRestDocuments.trace("Normalization complete")
    return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
  }

  /// Normalize a parsed JSON value (from `JSONSerialization`).
  public static func normalize(_ json: Any) throws -> Any {
    if let array = json as? [Any] {
      return try array.map { try normalizeValue($0) }
    }

    if let dict = json as? [String: Any] {
      if let fields = dict["fields"] as? [String: Any] {
        return try fields.mapValues { try normalizeValue($0) }
      }

      if let documents = dict["documents"] as? [[String: Any]] {
        return try documents.map { try normalize($0) }
      }

      if let documentResults = dict["documentResults"] as? [[String: Any]] {
        return try documentResults.compactMap { resultDict -> Any? in
          guard let doc = resultDict["document"] as? [String: Any] else { return nil }
          return try normalize(doc)
        }
      }

      if let value = dict["value"] as? [String: Any] {
        return try normalizeValue(value)
      }

      return try normalizeValue(json)
    }

    return json
  }

  static func normalizeValue(_ json: Any) throws -> Any {
    guard let dict = json as? [String: Any] else { return json }

    if dict.keys.contains("nullValue") {
      return NSNull()
    }

    if let val = dict["booleanValue"] {
      if let str = val as? String { return str == "true" }
      if let b = val as? Bool { return b }
    }

    if let val = dict["integerValue"] {
      if let str = val as? String, let i = Int64(str) { return i }
      if let n = val as? NSNumber { return n.int64Value }
    }

    if let val = dict["doubleValue"] {
      if let str = val as? String, let d = Double(str) { return d }
      if let n = val as? NSNumber { return n.doubleValue }
    }

    if let val = dict["stringValue"] as? String { return val }
    if let val = dict["timestampValue"] as? String { return val }
    if let ts = dict["timestampValue"] as? [String: Any],
       let secStr = ts["seconds"] as? String,
       let seconds = Double(secStr) {
      let rawNanos = (ts["nanoseconds"] as? Double) ?? (ts["nanos"] as? Double) ?? 0
      let nanos = rawNanos / 1_000_000_000
      let date = Date(timeIntervalSince1970: seconds + nanos)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      return formatter.string(from: date)
    }
    if let val = dict["referenceValue"] as? String { return val }
    if let val = dict["bytesValue"] as? String { return val }

    if let val = dict["geoPointValue"] as? [String: Any] {
      return val
    }

    if let val = dict["arrayValue"] as? [String: Any] {
      let values = val["values"] as? [Any] ?? []
      return try values.map { try normalizeValue($0) }
    }

    if let val = dict["mapValue"] as? [String: Any] {
      let fields = val["fields"] as? [String: Any] ?? [:]
      var result: [String: Any] = [:]
      for (key, value) in fields {
        result[key] = try normalizeValue(value)
      }
      return result
    }

    return dict
  }
}

extension JSONDecoder {
  /// Decode a Firestore REST API response directly using a standard `JSONDecoder`.
  ///
  /// Internally normalizes the Firestore typed-value format to flat JSON
  /// before decoding, so your model types don't need any Firestore-specific
  /// annotations.
  ///
  /// Configure the decoder's `dateDecodingStrategy` to `.iso8601` (with
  /// fractional seconds) and `dataDecodingStrategy` to `.base64` for full
  /// Firestore compatibility.
  ///
  /// ```swift
  /// let decoder = JSONDecoder()
  /// decoder.dateDecodingStrategy = .custom { decoder in
  ///   let container = try decoder.singleValueContainer()
  ///   let raw = try container.decode(String.self)
  ///   let formatter = ISO8601DateFormatter()
  ///   formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  ///   return formatter.date(from: raw)!
  /// }
  /// decoder.dataDecodingStrategy = .base64
  /// let user = try decoder.firestoreDecode(User.self, from: responseData)
  /// ```
  public func firestoreDecode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let normalized = try FirestoreNormalizer.normalize(data)
    return try decode(type, from: normalized)
  }
}
