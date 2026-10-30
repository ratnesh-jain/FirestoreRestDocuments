import Foundation
import FirestoreRestDocuments
import Logging

/// Connection settings shared by the CLI and the MCP server.
public struct FirestoreConnectionOptions: Sendable {
  public var project: String?
  public var database: String?
  public var token: String?
  public var tokenFile: String?
  public var serviceAccount: String?
  public var apiKey: String?
  public var emulatorHost: String?
  public var baseURL: String?
  public var verbose: Bool

  public init(
    project: String? = nil,
    database: String? = nil,
    token: String? = nil,
    tokenFile: String? = nil,
    serviceAccount: String? = nil,
    apiKey: String? = nil,
    emulatorHost: String? = nil,
    baseURL: String? = nil,
    verbose: Bool = false
  ) {
    self.project = project
    self.database = database
    self.token = token
    self.tokenFile = tokenFile
    self.serviceAccount = serviceAccount
    self.apiKey = apiKey
    self.emulatorHost = emulatorHost
    self.baseURL = baseURL
    self.verbose = verbose
  }

  /// Resolves a `FirestoreConfig` from explicit options, then environment
  /// variables. When `requiresCredentials` is false (for example, a CLI
  /// dry run), a placeholder token is used instead of failing.
  public func resolve(
    requiresCredentials: Bool = true,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> ResolvedFirestoreConnection {
    var resolvedToken = try resolveToken(environment: environment)

    var serviceAccount: FirestoreServiceAccount?
    if resolvedToken == nil, let path = serviceAccountPath(environment: environment) {
      serviceAccount = try loadServiceAccount(at: path)
    }

    let projectId = try resolveProjectId(serviceAccount: serviceAccount, environment: environment)
    let databaseId = database
      ?? environment["FIRESTORE_DATABASE_ID"]
      ?? "(default)"
    let resolvedAPIKey = apiKey ?? environment["FIRESTORE_API_KEY"] ?? environment["GOOGLE_API_KEY"]
    let emulatorHost = self.emulatorHost ?? environment["FIRESTORE_EMULATOR_HOST"]

    if resolvedToken == nil, serviceAccount == nil {
      if let emulatorHost, !emulatorHost.isEmpty {
        resolvedToken = "owner"
      } else if resolvedAPIKey == nil {
        if requiresCredentials {
          throw FirestoreOperationError(
            """
            No credentials found. Provide one of:
              --service-account path/to/key.json  (or GOOGLE_APPLICATION_CREDENTIALS)
              --token <oauth2-token>              (or FIRESTORE_ACCESS_TOKEN)
              --token-file path/to/token
              --api-key <key>                     (or FIRESTORE_API_KEY)
            """
          )
        }
        // Dry runs only print the request, so a placeholder keeps the rest of
        // the pipeline (which expects a token) working.
        resolvedToken = "dry-run"
      }
    }

    var config: FirestoreConfig
    if let serviceAccount {
      config = FirestoreConfig(
        projectId: projectId,
        databaseId: databaseId,
        serviceAccount: serviceAccount,
        apiKey: resolvedAPIKey
      )
    } else {
      config = FirestoreConfig(
        projectId: projectId,
        databaseId: databaseId,
        accessToken: resolvedToken,
        apiKey: resolvedAPIKey
      )
    }

    if let baseURL, !baseURL.isEmpty {
      config.baseURL = baseURL
    } else if let emulatorHost, !emulatorHost.isEmpty {
      config.baseURL = emulatorBaseURL(host: emulatorHost)
    }

    return ResolvedFirestoreConnection(
      config: config,
      logLevel: resolveLogLevel(environment: environment)
    )
  }

  private func serviceAccountPath(environment: [String: String]) -> String? {
    serviceAccount ?? environment["GOOGLE_APPLICATION_CREDENTIALS"]
  }

  private func loadServiceAccount(at path: String) throws -> FirestoreServiceAccount {
    let expandedPath = (path as NSString).expandingTildeInPath
    let data: Data
    do {
      data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
    } catch {
      throw FirestoreOperationError(
        "Could not read service account key '\(path)': \(error.localizedDescription)")
    }
    do {
      return try JSONDecoder().decode(FirestoreServiceAccount.self, from: data)
    } catch {
      throw FirestoreOperationError(
        "Could not decode service account key '\(path)': \(error.localizedDescription)")
    }
  }

  private func resolveProjectId(
    serviceAccount: FirestoreServiceAccount?,
    environment: [String: String]
  ) throws -> String {
    let candidates: [String?] = [
      project,
      environment["FIRESTORE_PROJECT_ID"],
      environment["GOOGLE_CLOUD_PROJECT"],
      environment["GCLOUD_PROJECT"],
      serviceAccount?.projectId,
    ]
    for candidate in candidates {
      if let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
         !candidate.isEmpty {
        return candidate
      }
    }
    throw FirestoreOperationError(
      """
      No project ID found. Pass --project, set FIRESTORE_PROJECT_ID, or provide \
      a service account key that contains project_id.
      """
    )
  }

  private func resolveToken(environment: [String: String]) throws -> String? {
    if let token, !token.isEmpty {
      return token
    }
    if let environmentToken = environment["FIRESTORE_ACCESS_TOKEN"]
      ?? environment["GOOGLE_OAUTH_ACCESS_TOKEN"],
      !environmentToken.isEmpty {
      return environmentToken
    }
    guard let tokenFile else { return nil }

    let path = (tokenFile as NSString).expandingTildeInPath
    do {
      let contents = try String(contentsOfFile: path, encoding: .utf8)
      let token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !token.isEmpty else {
        throw FirestoreOperationError("Token file '\(tokenFile)' is empty.")
      }
      return token
    } catch let error as FirestoreOperationError {
      throw error
    } catch {
      throw FirestoreOperationError(
        "Could not read token file '\(tokenFile)': \(error.localizedDescription)")
    }
  }

  private func resolveLogLevel(environment: [String: String]) -> Logger.Level {
    if verbose { return .debug }
    if let raw = environment["FIRESTORE_LOG_LEVEL"],
       let level = Logger.Level(rawValue: raw.lowercased()) {
      return level
    }
    return .error
  }

  private func emulatorBaseURL(host: String) -> String {
    var base = host.contains("://") ? host : "http://\(host)"
    while base.hasSuffix("/") { base.removeLast() }
    if !base.hasSuffix("/v1") { base += "/v1" }
    return base
  }
}

public struct ResolvedFirestoreConnection: Sendable {
  public let config: FirestoreConfig
  public let logLevel: Logger.Level

  public init(config: FirestoreConfig, logLevel: Logger.Level) {
    self.config = config
    self.logLevel = logLevel
  }
}
