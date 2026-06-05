import Logging

extension Logger {
  static let firestoreRestDocuments: Logger = {
    var logger = Logger(label: "com.firestorerestdocuments")
    logger.logLevel = .debug
    return logger
  }()
}
