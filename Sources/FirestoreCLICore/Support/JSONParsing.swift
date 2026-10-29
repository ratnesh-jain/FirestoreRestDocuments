import Foundation

enum JSONParsing {
  static func any(from data: Data, context: String = "JSON") throws -> Any {
    do {
      return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    } catch {
      throw CLIError("Invalid \(context): \(error.localizedDescription)")
    }
  }

  static func object(from data: Data, context: String) throws -> [String: Any] {
    let value = try any(from: data, context: context)
    guard let object = value as? [String: Any] else {
      throw CLIError("Expected a JSON object for \(context)")
    }
    return object
  }
}
