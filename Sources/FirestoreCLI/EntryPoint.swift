import FirestoreCLICore
import Logging

@main
struct FirestoreCLIEntryPoint {
  static func main() async {
    LoggingSystem.bootstrap { label in
      var handler = StreamLogHandler.standardError(label: label)
      // Filtering happens per logger; keep the handler permissive.
      handler.logLevel = .trace
      return handler
    }

    await FirestoreCommand.main()
  }
}
