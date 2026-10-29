import Foundation

/// A user-facing error. ArgumentParser prints `description` and exits with code 1.
struct CLIError: Error, CustomStringConvertible {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var description: String { message }
}
