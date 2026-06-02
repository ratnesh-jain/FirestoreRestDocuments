import Dependencies
import FirestoreRestDocuments

extension FirestoreDocument {
  public static var live: FirestoreDocument {
    @Dependency(\.defaultFirestoreConfig) var config
    return FirestoreDocument(config: config)
  }
}
