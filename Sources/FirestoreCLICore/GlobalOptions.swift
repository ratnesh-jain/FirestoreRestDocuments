import ArgumentParser
import Foundation
import FirestoreOperations
import Logging

/// Options shared by every command: connection, authentication, and output.
public struct GlobalOptions: ParsableArguments {
  @Option(
    name: [.customShort("p"), .long],
    help: """
    Google Cloud project ID. Falls back to FIRESTORE_PROJECT_ID, \
    GOOGLE_CLOUD_PROJECT, GCLOUD_PROJECT, then the service account's project.
    """
  )
  var project: String?

  @Option(
    name: [.customShort("d"), .long],
    help: "Firestore database ID. Defaults to FIRESTORE_DATABASE_ID or \"(default)\"."
  )
  var database: String?

  @Option(
    name: [.customShort("t"), .long],
    help: "OAuth2 access token or Firebase ID token. Prefer FIRESTORE_ACCESS_TOKEN."
  )
  var token: String?

  @Option(
    name: .customLong("token-file"),
    help: "Path to a file containing an access token."
  )
  var tokenFile: String?

  @Option(
    name: [.customShort("s"), .customLong("service-account")],
    help: "Path to a Google service account JSON key. Falls back to GOOGLE_APPLICATION_CREDENTIALS."
  )
  var serviceAccount: String?

  @Option(
    name: .customLong("api-key"),
    help: "Google API key, used only when no access token is available."
  )
  var apiKey: String?

  @Option(
    name: .customLong("emulator-host"),
    help: "Firestore emulator host, for example localhost:8080. Falls back to FIRESTORE_EMULATOR_HOST."
  )
  var emulatorHost: String?

  @Option(
    name: .customLong("base-url"),
    help: "Override the Firestore REST base URL."
  )
  var baseURL: String?

  @Flag(
    name: .customLong("compact"),
    help: "Emit compact JSON instead of pretty-printed JSON."
  )
  var compact = false

  @Flag(
    name: [.customShort("v"), .long],
    help: "Log debug details to stderr."
  )
  var verbose = false

  public init() {}

  var connectionOptions: FirestoreConnectionOptions {
    FirestoreConnectionOptions(
      project: project,
      database: database,
      token: token,
      tokenFile: tokenFile,
      serviceAccount: serviceAccount,
      apiKey: apiKey,
      emulatorHost: emulatorHost,
      baseURL: baseURL,
      verbose: verbose
    )
  }

  func resolveConnection(
    requiresCredentials: Bool = true,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> ResolvedFirestoreConnection {
    try connectionOptions.resolve(
      requiresCredentials: requiresCredentials,
      environment: environment
    )
  }
}

typealias ResolvedConnection = ResolvedFirestoreConnection
