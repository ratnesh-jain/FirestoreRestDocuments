import FirestoreMCPServer
import FirestoreOperations
import Foundation
import Logging
import MCP

@main
struct FirestoreMCPMain {
  static func main() async {
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardError(label: label)
      handler.logLevel = .trace
      return handler
    }

    do {
      let connection = try FirestoreConnectionOptions().resolve()
      let server = await FirestoreMCPService.makeServer(connection: connection)
      try await server.start(transport: StdioTransport())
      await server.waitUntilCompleted()
    } catch {
      let message = (error as? FirestoreOperationError)?.message ?? String(describing: error)
      FileHandle.standardError.write(Data("frd-mcp: \(message)\n".utf8))
      exit(1)
    }
  }
}
