import Dependencies
import FirestoreRestDocuments
import Logging

extension FirestoreDocument {
  public static var live: FirestoreDocument {
    @Dependency(\.defaultFirestoreConfig) var config
    @Dependency(\.defaultFirestoreLogLevel) var logLevel
    return FirestoreDocument(config: config, logLevel: logLevel)
  }
}
