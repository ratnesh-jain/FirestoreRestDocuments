import Foundation

public enum JSONParsing {
  public static func any(from data: Data, context: String = "JSON") throws -> Any {
    do {
      return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw FirestoreOperationError("Invalid \(context): \(error.localizedDescription)")
    }
  }

  public static func object(from data: Data, context: String) throws -> [String: Any] {
    let value = try any(from: data, context: context)
    guard let object = value as? [String: Any] else {
      throw FirestoreOperationError("Expected a JSON object for \(context)")
    }
    return object
  }
}
