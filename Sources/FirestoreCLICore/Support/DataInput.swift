import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Loads JSON from `--data`, a file, or standard input.
enum DataInput {
  static func load(data: String?, file: String?) throws -> Data {
    if let data {
      guard let bytes = data.data(using: .utf8) else {
        throw CLIError("Could not encode --data as UTF-8")
      }
      return bytes
    }

    if let file, file != "-" {
      let path = (file as NSString).expandingTildeInPath
      do {
        return try Data(contentsOf: URL(fileURLWithPath: path))
      } catch {
        throw CLIError("Could not read '\(file)': \(error.localizedDescription)")
      }
    }

    guard !stdinIsTTY else {
      throw CLIError("No input provided. Use --data, --file, or pipe JSON through stdin.")
    }
    return FileHandle.standardInput.readDataToEndOfFile()
  }

  private static var stdinIsTTY: Bool {
    isatty(STDIN_FILENO) == 1
  }
}
