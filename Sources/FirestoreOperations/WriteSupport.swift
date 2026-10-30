import Foundation
import FirestoreRestDocuments

public enum WriteSupport {
  public static func makeWrite(
    path: String,
    fields: [String: Any],
    updateMask: [String]?,
    createOnly: Bool,
    ifExists: Bool
  ) throws -> FirestoreWrite {
    let fieldsData = try DocumentPayload.fieldsData(fields)
    if createOnly {
      return FirestoreWrite(documentPath: path, storage: .create(fieldsData: fieldsData))
    }
    return FirestoreWrite(
      documentPath: path,
      storage: .update(
        fieldsData: fieldsData,
        updateMask: updateMask,
        exists: ifExists ? true : nil
      )
    )
  }

  /// Top-level field names, used as the update mask for merge-style updates.
  public static func mask(from fields: [String: Any]) throws -> [String] {
    let keys = fields.keys.sorted()
    guard !keys.isEmpty else {
      throw FirestoreOperationError("The document has no fields to update.")
    }
    return keys
  }

  public static func parseLabels(_ values: [String]) throws -> [String: String] {
    var labels: [String: String] = [:]
    for value in values {
      guard let separator = value.firstIndex(of: "=") else {
        throw FirestoreOperationError("Invalid --label '\(value)'. Expected key=value.")
      }
      let key = String(value[..<separator]).trimmingCharacters(in: .whitespaces)
      let labelValue = String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty else {
        throw FirestoreOperationError("Invalid --label '\(value)'. The key cannot be empty.")
      }
      labels[key] = labelValue
    }
    return labels
  }
}
