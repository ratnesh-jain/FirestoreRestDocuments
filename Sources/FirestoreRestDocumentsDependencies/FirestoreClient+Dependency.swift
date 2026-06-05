import Dependencies
import FirestoreRestDocuments
import Logging

// MARK: - Config dependency

extension DependencyValues {
  public var defaultFirestoreConfig: FirestoreConfig {
    get { self[DefaultFirestoreConfigKey.self] }
    set { self[DefaultFirestoreConfigKey.self] = newValue }
  }
}

private enum DefaultFirestoreConfigKey: TestDependencyKey {
  static let testValue = FirestoreConfig(projectId: "__test__")
  static let previewValue = FirestoreConfig(projectId: "__preview__")
}

extension DefaultFirestoreConfigKey: DependencyKey {
  static let liveValue = FirestoreConfig(projectId: "")
}

// MARK: - Log level dependency

extension DependencyValues {
  public var defaultFirestoreLogLevel: Logger.Level {
    get { self[DefaultFirestoreLogLevelKey.self] }
    set { self[DefaultFirestoreLogLevelKey.self] = newValue }
  }
}

private enum DefaultFirestoreLogLevelKey: TestDependencyKey {
  static let testValue = Logger.Level.debug
  static let previewValue = Logger.Level.debug
}

extension DefaultFirestoreLogLevelKey: DependencyKey {
  static let liveValue = Logger.Level.debug
}

// MARK: - FirestoreClient dependency

extension DependencyValues {
  public var firestoreClient: any FirestoreClient {
    get { self[FirestoreClientKey.self] }
    set { self[FirestoreClientKey.self] = newValue }
  }
}

private enum FirestoreClientKey: TestDependencyKey {
  static let testValue: any FirestoreClient = MockFirestoreClient()
  static let previewValue: any FirestoreClient = MockFirestoreClient()
}

extension FirestoreClientKey: DependencyKey {
  static var liveValue: any FirestoreClient {
    @Dependency(\.defaultFirestoreConfig) var config
    @Dependency(\.defaultFirestoreLogLevel) var logLevel
    return LiveFirestoreClient(config: config, logLevel: logLevel)
  }
}
