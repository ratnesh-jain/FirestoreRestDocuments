import Foundation

/// A user-facing operation error, shared by the CLI and the MCP server.
public struct FirestoreOperationError: Error, CustomStringConvertible, Sendable {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }

  public var description: String { message }
}
