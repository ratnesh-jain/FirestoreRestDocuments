import Foundation

enum FirestorePath {
  /// Normalizes a path to `collection/document[/collection/document...]`.
  static func normalize(_ raw: String) throws -> String {
    var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while path.hasPrefix("/") { path.removeFirst() }
    while path.hasSuffix("/") { path.removeLast() }

    guard !path.isEmpty else {
      throw CLIError("Path cannot be empty.")
    }

    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
    guard segments.allSatisfy({ !$0.isEmpty }) else {
      throw CLIError("Invalid path '\(raw)': paths cannot contain empty segments.")
    }
    return path
  }

  /// Validates and normalizes a document path (an even number of segments).
  static func document(_ raw: String) throws -> String {
    let path = try normalize(raw)
    let count = path.split(separator: "/").count
    guard count >= 2, count.isMultiple(of: 2) else {
      throw CLIError(
        """
        '\(path)' is not a document path. Expected a path like \
        'users/alice' or 'users/alice/orders/order1'.
        """
      )
    }
    return path
  }

  /// Validates and normalizes a collection path (an odd number of segments).
  static func collection(_ raw: String) throws -> String {
    let path = try normalize(raw)
    let count = path.split(separator: "/").count
    guard !count.isMultiple(of: 2) else {
      throw CLIError("'\(path)' is a document path, not a collection path.")
    }
    return path
  }

  /// Resolves a write target. A collection path gets `--id` appended, or a
  /// generated document ID when `generateID` is true.
  static func writeTarget(_ raw: String, id: String?, generateID: Bool) throws -> String {
    let path = try normalize(raw)
    let count = path.split(separator: "/").count

    if count.isMultiple(of: 2) {
      guard id == nil else {
        throw CLIError("--id can only be used when the path is a collection.")
      }
      return path
    }

    let documentID: String
    if let id {
      guard !id.isEmpty, !id.contains("/"), id != ".", id != ".." else {
        throw CLIError("Invalid document ID '\(id)'.")
      }
      documentID = id
    } else if generateID {
      documentID = autoID()
    } else {
      throw CLIError("'\(path)' is a collection. Provide a document ID.")
    }
    return "\(path)/\(documentID)"
  }

  /// Returns the last component of a full Firestore document name.
  static func documentID(fromFullName name: String) -> String {
    String(name.split(separator: "/").last ?? "")
  }

  /// Normalizes an optional document path used as a collection parent. An
  /// empty or missing value means the database root.
  static func parentDocument(_ raw: String?) throws -> String? {
    guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return try document(raw)
  }

  /// Generates a 20-character, Firestore-style random document ID.
  static func autoID() -> String {
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    var generator = SystemRandomNumberGenerator()
    return String((0..<20).map { _ in alphabet.randomElement(using: &generator)! })
  }

  /// Comma-separated field paths, as accepted by `--mask`.
  static func parseMask(_ raw: String) throws -> [String] {
    let fields = raw
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !fields.isEmpty else {
      throw CLIError("--mask must contain at least one field path.")
    }
    return fields
  }
}
