import CoreFoundation
import Foundation
import FirestoreRestDocuments

/// Converts between plain JSON documents, Firestore's typed REST wire format,
/// and the CLI's output representation.
public enum DocumentPayload {
  private static let wireDocumentKeys: Set<String> = ["fields", "name", "createTime", "updateTime"]

  private static let valueKeys: Set<String> = [
    "nullValue",
    "booleanValue",
    "integerValue",
    "doubleValue",
    "stringValue",
    "timestampValue",
    "referenceValue",
    "bytesValue",
    "geoPointValue",
    "arrayValue",
    "mapValue",
  ]

  // MARK: - Input

  public static func fields(from data: Data, config: FirestoreConfig) throws -> [String: Any] {
    let json = try JSONParsing.any(from: data, context: "document data")
    return try fields(fromJSON: json, config: config)
  }

  public static func fields(fromJSON json: Any, config: FirestoreConfig) throws -> [String: Any] {
    guard let object = json as? [String: Any] else {
      throw FirestoreOperationError("Document data must be a JSON object mapping field names to values.")
    }

    if isWireDocument(object) {
      return object["fields"] as? [String: Any] ?? [:]
    }

    return try object.mapValues { try typedValue($0, config: config, interpretTags: true) }
  }

  public static func fieldsData(_ fields: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(fields) else {
      throw FirestoreOperationError("Document data is not valid JSON.")
    }
    return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
  }

  /// Converts a document's typed `fields` map to plain JSON for display.
  public static func normalizedFields(_ fields: [String: Any]) throws -> [String: Any] {
    do {
      let normalized = try FirestoreNormalizer.normalize(["fields": fields])
      return normalized as? [String: Any] ?? [:]
    } catch {
      throw FirestoreOperationError("Could not normalize document fields: \(error.localizedDescription)")
    }
  }

  /// Builds the `{ id, name, createTime, updateTime, data }` summary used by
  /// `frd list` and the MCP list tool.
  public static func summary(fromWireDocument document: [String: Any]) throws -> [String: Any] {
    var item: [String: Any] = [:]
    if let name = document["name"] as? String {
      item["id"] = FirestorePath.documentID(fromFullName: name)
      item["name"] = name
    }
    if let createTime = document["createTime"] as? String {
      item["createTime"] = createTime
    }
    if let updateTime = document["updateTime"] as? String {
      item["updateTime"] = updateTime
    }
    let fields = document["fields"] as? [String: Any] ?? [:]
    item["data"] = try normalizedFields(fields)
    return item
  }

  // MARK: - Output values

  /// Converts a decoded `FirestoreValue` to a plain JSON-compatible value.
  public static func flatValue(_ value: FirestoreValue) -> Any {
    switch value {
    case .null:
      return NSNull()
    case .bool(let bool):
      return bool
    case .int(let int):
      return int
    case .double(let double):
      return double
    case .string(let string):
      return string
    case .bytes(let data):
      return data.base64EncodedString()
    case .timestamp(let date):
      let formatter = ISO8601DateFormatter()
      let fraction = date.timeIntervalSince1970 - date.timeIntervalSince1970.rounded(.down)
      formatter.formatOptions = fraction == 0
        ? [.withInternetDateTime]
        : [.withInternetDateTime, .withFractionalSeconds]
      return formatter.string(from: date)
    case .geoPoint(let latitude, let longitude):
      return ["latitude": latitude, "longitude": longitude]
    case .reference(let reference):
      return reference
    case .array(let items):
      return items.map(flatValue)
    case .map(let fields):
      return fields.mapValues(flatValue)
    case .document(_, let fields):
      return fields.mapValues(flatValue)
    }
  }

  // MARK: - Flat JSON -> Firestore wire format

  /// True when the JSON looks like a Firestore document (`{"fields": {...}}`)
  /// rather than a flat map of field names to values.
  public static func isWireDocument(_ object: [String: Any]) -> Bool {
    guard let fields = object["fields"] as? [String: Any] else { return false }
    guard object.keys.allSatisfy(wireDocumentKeys.contains) else { return false }
    guard !fields.isEmpty else { return true }
    return fields.values.allSatisfy { value in
      guard let wrapper = value as? [String: Any] else { return false }
      return wrapper.keys.contains(where: valueKeys.contains)
    }
  }

  private static func typedValue(
    _ value: Any,
    config: FirestoreConfig,
    interpretTags: Bool
  ) throws -> Any {
    if value is NSNull {
      return ["nullValue": NSNull()]
    }

    if let number = value as? NSNumber {
      if CFGetTypeID(number) == CFBooleanGetTypeID() {
        return ["booleanValue": number.boolValue]
      }
      if CFNumberIsFloatType(number) {
        return ["doubleValue": number.doubleValue]
      }
      return ["integerValue": String(number.int64Value)]
    }

    if let string = value as? String {
      return ["stringValue": string]
    }

    if let array = value as? [Any] {
      let values = try array.map { try typedValue($0, config: config, interpretTags: interpretTags) }
      return ["arrayValue": ["values": values]]
    }

    if let object = value as? [String: Any] {
      if interpretTags, let special = try specialValue(object, config: config) {
        return special
      }
      let fields = try object.mapValues {
        try typedValue($0, config: config, interpretTags: interpretTags)
      }
      return ["mapValue": ["fields": fields]]
    }

    throw FirestoreOperationError("Unsupported JSON value: \(value)")
  }

  // MARK: - Typed value tags

  private static let tagNames = [
    "$timestamp", "$reference", "$geopoint", "$bytes", "$integer", "$double", "$literal",
  ]

  private static func specialValue(
    _ object: [String: Any],
    config: FirestoreConfig
  ) throws -> Any? {
    guard object.count == 1, let (tag, value) = object.first, tag.hasPrefix("$") else {
      return nil
    }

    switch tag {
    case "$timestamp":
      guard let string = value as? String else {
        throw FirestoreOperationError("$timestamp expects a string, for example {\"$timestamp\": \"2024-06-15T10:30:00Z\"}.")
      }
      guard isValidTimestamp(string) else {
        throw FirestoreOperationError("Invalid $timestamp '\(string)'. Use an ISO 8601 / RFC 3339 value.")
      }
      return ["timestampValue": string]

    case "$reference":
      guard let string = value as? String, !string.isEmpty else {
        throw FirestoreOperationError("$reference expects a document path string.")
      }
      let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
      let fullPath = trimmed.hasPrefix("projects/")
        ? trimmed
        : "projects/\(config.projectId)/databases/\(config.databaseId)/documents/\(trimmed)"
      return ["referenceValue": fullPath]

    case "$geopoint":
      if let coordinates = value as? [String: Any],
         let latitude = number(coordinates["latitude"]),
         let longitude = number(coordinates["longitude"]) {
        return ["geoPointValue": ["latitude": latitude, "longitude": longitude]]
      }
      if let coordinates = value as? [Any],
         coordinates.count == 2,
         let latitude = number(coordinates[0]),
         let longitude = number(coordinates[1]) {
        return ["geoPointValue": ["latitude": latitude, "longitude": longitude]]
      }
      throw FirestoreOperationError("$geopoint expects {\"latitude\": .., \"longitude\": ..} or [lat, lon].")

    case "$bytes":
      guard let string = value as? String, Data(base64Encoded: string) != nil else {
        throw FirestoreOperationError("$bytes expects a base64-encoded string.")
      }
      return ["bytesValue": string]

    case "$integer":
      let int: Int64
      if let string = value as? String {
        guard let parsed = Int64(string) else {
          throw FirestoreOperationError("$integer expects a whole number or a numeric string.")
        }
        int = parsed
      } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
        let double = number.doubleValue
        guard double == double.rounded(), double >= Double(Int64.min), double <= Double(Int64.max) else {
          throw FirestoreOperationError("$integer expects a whole number.")
        }
        int = Int64(double)
      } else {
        throw FirestoreOperationError("$integer expects a whole number or a numeric string.")
      }
      return ["integerValue": String(int)]

    case "$double":
      if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
        return ["doubleValue": number.doubleValue]
      }
      if let string = value as? String, let double = Double(string) {
        return ["doubleValue": double]
      }
      throw FirestoreOperationError("$double expects a number or a numeric string.")

    case "$literal":
      guard let object = value as? [String: Any] else {
        throw FirestoreOperationError("$literal expects a JSON object.")
      }
      let fields = try object.mapValues {
        try typedValue($0, config: config, interpretTags: false)
      }
      return ["mapValue": ["fields": fields]]

    default:
      throw FirestoreOperationError(
        """
        Unknown typed value '\(tag)'. Supported tags: \(tagNames.joined(separator: ", ")). \
        Use {"$literal": {...}} to write a map containing a '$' key.
        """
      )
    }
  }

  private static func number(_ value: Any?) -> Double? {
    if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
      return number.doubleValue
    }
    if let string = value as? String {
      return Double(string)
    }
    return nil
  }

  private static func isValidTimestamp(_ string: String) -> Bool {
    // RFC 3339, allowing any number of fractional digits and a numeric offset.
    let pattern = #"^\d{4}-\d{2}-\d{2}[Tt ]\d{2}:\d{2}:\d{2}(\.\d+)?([Zz]|[+-]\d{2}:\d{2})$"#
    return string.range(of: pattern, options: .regularExpression) != nil
  }
}
