import Foundation
import FirestoreRestDocuments

/// Parses a batch-write definition file into `FirestoreWrite` values.
///
/// Accepted shapes:
/// ```json
/// [
///   {"op": "create", "path": "users/u1", "data": {"name": "Alice"}},
///   {"op": "update", "path": "users/u1", "data": {"name": "Bob"}, "mask": ["name"]},
///   {"op": "delete", "path": "users/u2"}
/// ]
/// ```
/// or `{"writes": [...]}` / `{"operations": [...]}`.
enum BatchWriteFile {
  static func writes(from json: Any, config: FirestoreConfig) throws -> [FirestoreWrite] {
    let operations: [Any]
    if let array = json as? [Any] {
      operations = array
    } else if let object = json as? [String: Any],
              let writes = (object["writes"] as? [Any]) ?? (object["operations"] as? [Any]) {
      operations = writes
    } else {
      throw CLIError(
        "The batch file must be a JSON array of operations, or an object with a \"writes\" array."
      )
    }

    guard !operations.isEmpty else {
      throw CLIError("The batch file contains no operations.")
    }
    return try operations.map { try write(from: $0, config: config) }
  }

  private static func write(from json: Any, config: FirestoreConfig) throws -> FirestoreWrite {
    guard let object = json as? [String: Any] else {
      throw CLIError("Each batch operation must be a JSON object.")
    }
    guard let operation = (object["op"] as? String) ?? (object["operation"] as? String) else {
      throw CLIError("Each batch operation needs an \"op\" field (create, set, update, delete).")
    }
    guard let rawPath = object["path"] as? String else {
      throw CLIError("Batch operation '\(operation)' is missing a \"path\".")
    }
    let path = try FirestorePath.document(rawPath)
    let name = operation.lowercased()

    if name == "delete" {
      guard object["data"] == nil else {
        throw CLIError("Delete operation for '\(path)' cannot include \"data\".")
      }
      return .delete(at: path)
    }

    guard let data = object["data"] else {
      throw CLIError("Batch operation '\(name)' for '\(path)' is missing \"data\".")
    }
    let fields = try DocumentPayload.fields(fromJSON: data, config: config)
    let fieldsData = try DocumentPayload.fieldsData(fields)
    let exists = object["exists"] as? Bool

    switch name {
    case "create":
      guard object["mask"] == nil else {
        throw CLIError("Create operation for '\(path)' cannot include a \"mask\".")
      }
      return FirestoreWrite(documentPath: path, storage: .create(fieldsData: fieldsData))

    case "set":
      let updateMask = try mask(from: object["mask"])
      return FirestoreWrite(
        documentPath: path,
        storage: .update(fieldsData: fieldsData, updateMask: updateMask, exists: exists)
      )

    case "update":
      let updateMask: [String]?
      if object["mask"] != nil {
        updateMask = try mask(from: object["mask"])
      } else if object["replace"] as? Bool == true {
        updateMask = nil
      } else {
        updateMask = try WriteSupport.mask(from: fields)
      }
      return FirestoreWrite(
        documentPath: path,
        storage: .update(fieldsData: fieldsData, updateMask: updateMask, exists: exists)
      )

    default:
      throw CLIError(
        "Unknown batch operation '\(operation)' for '\(path)'. Use create, set, update, or delete."
      )
    }
  }

  private static func mask(from value: Any?) throws -> [String]? {
    guard let value else { return nil }
    if let string = value as? String {
      return try FirestorePath.parseMask(string)
    }
    if let array = value as? [String] {
      let fieldPaths = array
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
      guard !fieldPaths.isEmpty else {
        throw CLIError("\"mask\" must contain at least one field path.")
      }
      return fieldPaths
    }
    throw CLIError("\"mask\" must be a comma-separated string or an array of field paths.")
  }
}
