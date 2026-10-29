import ArgumentParser
import Foundation
import FirestoreRestDocuments
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
}

struct ResolvedConnection {
  let config: FirestoreConfig
  let logLevel: Logger.Level
}

extension GlobalOptions {
  func resolveConnection(
    requiresCredentials: Bool = true,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> ResolvedConnection {
    var resolvedToken = try resolveToken(environment: environment)

    var serviceAccount: FirestoreServiceAccount?
    if resolvedToken == nil, let path = serviceAccountPath(environment: environment) {
      serviceAccount = try loadServiceAccount(at: path)
    }

    let projectId = try resolveProjectId(serviceAccount: serviceAccount, environment: environment)
    let databaseId = self.database
      ?? environment["FIRESTORE_DATABASE_ID"]
      ?? "(default)"
    let resolvedAPIKey = apiKey ?? environment["FIRESTORE_API_KEY"] ?? environment["GOOGLE_API_KEY"]
    let emulatorHost = self.emulatorHost ?? environment["FIRESTORE_EMULATOR_HOST"]

    if resolvedToken == nil, serviceAccount == nil {
      if let emulatorHost, !emulatorHost.isEmpty {
        resolvedToken = "owner"
      } else if resolvedAPIKey == nil {
        if requiresCredentials {
          throw CLIError(
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

    return ResolvedConnection(config: config, logLevel: resolveLogLevel(environment: environment))
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
      throw CLIError("Could not read service account key '\(path)': \(error.localizedDescription)")
    }
    do {
      return try JSONDecoder().decode(FirestoreServiceAccount.self, from: data)
    } catch {
      throw CLIError("Could not decode service account key '\(path)': \(error.localizedDescription)")
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
      if let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
        return candidate
      }
    }
    throw CLIError(
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
    if let environmentToken = environment["FIRESTORE_ACCESS_TOKEN"] ?? environment["GOOGLE_OAUTH_ACCESS_TOKEN"],
       !environmentToken.isEmpty {
      return environmentToken
    }
    guard let tokenFile else { return nil }

    let path = (tokenFile as NSString).expandingTildeInPath
    do {
      let contents = try String(contentsOfFile: path, encoding: .utf8)
      let token = contents.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !token.isEmpty else {
        throw CLIError("Token file '\(tokenFile)' is empty.")
      }
      return token
    } catch let error as CLIError {
      throw error
    } catch {
      throw CLIError("Could not read token file '\(tokenFile)': \(error.localizedDescription)")
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
