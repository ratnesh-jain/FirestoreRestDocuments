import Logging

extension Logger {
  nonisolated(unsafe) public static var defaultFirestoreLogLevel: Logger.Level = .debug

  /// The global shared logger for the FirestoreRestDocuments library.
  /// Its level is set from `defaultFirestoreLogLevel` at access time.
  static var firestoreRestDocuments: Logger {
    var logger = Logger(label: "com.firestorerestdocuments")
    logger.logLevel = defaultFirestoreLogLevel
    return logger
  }
}
