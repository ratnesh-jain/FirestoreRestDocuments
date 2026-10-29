import Foundation
import FirestoreRestDocuments
import Logging

/// Per-command runtime state: an authenticated client plus JSON output helpers.
struct CLIContext {
  let config: FirestoreConfig
  let database: FirestoreDocument
  let compact: Bool

  init(
    _ options: GlobalOptions,
    requiresCredentials: Bool = true,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    let resolved = try options.resolveConnection(
      requiresCredentials: requiresCredentials,
      environment: environment
    )
    Logger.defaultFirestoreLogLevel = resolved.logLevel
    self.config = resolved.config
    self.database = FirestoreDocument(config: resolved.config, logLevel: resolved.logLevel)
    self.compact = options.compact
  }

  // MARK: - Output

  func writeJSON(_ object: Any) throws {
    guard JSONSerialization.isValidJSONObject(object) else {
      throw CLIError("Internal error: attempted to print invalid JSON.")
    }
    var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
    if !compact {
      options.insert(.prettyPrinted)
    }
    let data = try JSONSerialization.data(withJSONObject: object, options: options)
    write(data)
  }

  func writeEncodable<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = compact
      ? [.sortedKeys]
      : [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    write(try encoder.encode(value))
  }

  func writeCommitResult(
    _ response: FirestoreCommitResponse,
    operation: String,
    path: String? = nil,
    paths: [String]? = nil
  ) throws {
    var result: [String: Any] = [
      "operation": operation,
      "commitTime": response.commitTime,
    ]
    if let path { result["path"] = path }
    if let paths { result["paths"] = paths }
    if let updateTime = response.writeResults.first?.updateTime {
      result["updateTime"] = updateTime
    }
    if !response.writeResults.isEmpty {
      result["writeResults"] = response.writeResults.map { entry -> [String: Any] in
        var writeResult: [String: Any] = [:]
        if let updateTime = entry.updateTime {
          writeResult["updateTime"] = updateTime
        }
        return writeResult
      }
    }
    try writeJSON(result)
  }

  func writeDryRun(writes: [FirestoreWrite], labels: [String: String]?, atomic: Bool) throws {
    let body = atomic
      ? try database.makeCommitBody(writes: writes)
      : try database.makeBatchWriteBody(writes: writes, labels: labels)
    let request = try JSONParsing.any(from: body, context: "request body")
    try writeJSON(["dryRun": true, "request": request])
  }

  private func write(_ data: Data) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }
}
