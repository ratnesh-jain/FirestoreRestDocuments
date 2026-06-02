import Foundation

public enum FirestoreParsingError: Error, LocalizedError, Sendable {
  case invalidValueFormat(String)
  case unknownValueType(String)
  case decodingFailed(String)
  case encodingFailed(String)
  case invalidDocumentData(String)
  case typeMismatch(expected: String, actual: String)
  case keyNotFound(String)

  public var errorDescription: String? {
    switch self {
    case .invalidValueFormat(let msg):
      return "Invalid Firestore value format: \(msg)"
    case .unknownValueType(let msg):
      return "Unknown Firestore value type: \(msg)"
    case .decodingFailed(let msg):
      return "Decoding failed: \(msg)"
    case .encodingFailed(let msg):
      return "Encoding failed: \(msg)"
    case .invalidDocumentData(let msg):
      return "Invalid document data: \(msg)"
    case .typeMismatch(let expected, let actual):
      return "Type mismatch: expected \(expected), got \(actual)"
    case .keyNotFound(let key):
      return "Key not found: \(key)"
    }
  }
}
