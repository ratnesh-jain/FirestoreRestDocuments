import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import Logging

public struct FirestoreConfig: Sendable {
  public var projectId: String
  public var databaseId: String
  public var accessToken: String?
  public var apiKey: String?
  public var accessTokenProvider: (any FirestoreAccessTokenProvider)?
  /// Base URL for the Firestore REST API. Override this to target an emulator.
  public var baseURL: String

  public static let defaultBaseURL = "https://firestore.googleapis.com/v1"

  nonisolated(unsafe) public static var shared = FirestoreConfig(projectId: "")

  public init(
    projectId: String,
    databaseId: String = "(default)",
    accessToken: String? = nil,
    apiKey: String? = nil,
    accessTokenProvider: (any FirestoreAccessTokenProvider)? = nil,
    baseURL: String = FirestoreConfig.defaultBaseURL
  ) {
    self.projectId = projectId
    self.databaseId = databaseId
    self.accessToken = accessToken
    self.apiKey = apiKey
    self.accessTokenProvider = accessTokenProvider ?? (accessToken.map { StaticAccessTokenProvider(token: $0) })
    self.baseURL = baseURL
  }

  public func resolveAccessToken() async throws -> String? {
    if let provider = accessTokenProvider {
      return try await provider.accessToken()
    }
    return accessToken
  }

  // MARK: - Service account convenience

  public init(
    projectId: String,
    databaseId: String = "(default)",
    serviceAccount: FirestoreServiceAccount,
    apiKey: String? = nil,
    scopes: [String] = ["https://www.googleapis.com/auth/datastore"]
  ) {
    let provider = ServiceAccountTokenProvider(serviceAccount: serviceAccount, scopes: scopes)
    self.init(projectId: projectId, databaseId: databaseId, apiKey: apiKey, accessTokenProvider: provider)
  }

  public init(
    projectId: String,
    databaseId: String = "(default)",
    serviceAccountKeyData: Data,
    apiKey: String? = nil,
    scopes: [String] = ["https://www.googleapis.com/auth/datastore"]
  ) throws {
    let provider = try ServiceAccountTokenProvider(keyData: serviceAccountKeyData, scopes: scopes)
    self.init(projectId: projectId, databaseId: databaseId, apiKey: apiKey, accessTokenProvider: provider)
  }

  public init(
    projectId: String,
    databaseId: String = "(default)",
    serviceAccountKeyFileAtPath path: String,
    apiKey: String? = nil,
    scopes: [String] = ["https://www.googleapis.com/auth/datastore"]
  ) throws {
    let provider = try ServiceAccountTokenProvider(keyFileAtPath: path, scopes: scopes)
    self.init(projectId: projectId, databaseId: databaseId, apiKey: apiKey, accessTokenProvider: provider)
  }

  public init(
    projectId: String,
    databaseId: String = "(default)",
    serviceAccountKeyPath path: String,
    apiKey: String? = nil,
    scopes: [String] = ["https://www.googleapis.com/auth/datastore"]
  ) throws {
    try self.init(projectId: projectId, databaseId: databaseId, serviceAccountKeyFileAtPath: path, apiKey: apiKey, scopes: scopes)
  }

  var documentsBaseURL: String {
    "\(Self.normalizedBaseURL(baseURL))/projects/\(Self.percentEncodedComponent(projectId))/databases/\(Self.percentEncodedComponent(databaseId))/documents"
  }

  func makeRequest(path: String, queryItems: [URLQueryItem] = [], accessToken: String? = nil) throws -> URLRequest {
    guard !projectId.trimmingCharacters(in: .whitespaces).isEmpty else {
      Logger.firestoreRestDocuments.error("projectId is empty or missing")
      throw FirestoreParsingError.invalidDocumentData(
        """
        FirestoreConfig.projectId is empty or missing.

        Configure it before making requests:

          prepareDependencies {
            $0.defaultFirestoreConfig = FirestoreConfig(
              projectId: "my-project",
              accessToken: token
            )
          }

        Or set FirestoreConfig.shared directly.
        """
      )
    }
    guard var url = URL(string: "\(documentsBaseURL)/\(Self.percentEncodedPath(path))") else {
      throw FirestoreParsingError.invalidDocumentData("Could not build a URL for path '\(path)'.")
    }
    let resolvedAccessToken = accessToken ?? self.accessToken
    var items = queryItems
    if let key = apiKey, resolvedAccessToken == nil {
      items.append(URLQueryItem(name: "key", value: key))
    }
    if !items.isEmpty {
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw FirestoreParsingError.invalidDocumentData("Invalid URL")
      }
      components.queryItems = (components.queryItems ?? []) + items
      url = components.url!
    }
    var req = URLRequest(url: url)
    Logger.firestoreRestDocuments.debug("Request URL: \(url.absoluteString)")
    if let token = resolvedAccessToken {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return req
  }

  func makeRequest(url: URL, accessToken: String? = nil) -> URLRequest {
    let resolvedAccessToken = accessToken ?? self.accessToken
    var req = URLRequest(url: url)
    if let token = resolvedAccessToken {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    return req
  }

  var batchGetURL: URL {
    URL(string: "\(Self.normalizedBaseURL(baseURL))/projects/\(Self.percentEncodedComponent(projectId))/databases/\(Self.percentEncodedComponent(databaseId))/documents:batchGet")!
  }

  var commitURL: URL {
    URL(string: "\(Self.normalizedBaseURL(baseURL))/projects/\(Self.percentEncodedComponent(projectId))/databases/\(Self.percentEncodedComponent(databaseId))/documents:commit")!
  }

  var batchWriteURL: URL {
    URL(string: "\(Self.normalizedBaseURL(baseURL))/projects/\(Self.percentEncodedComponent(projectId))/databases/\(Self.percentEncodedComponent(databaseId))/documents:batchWrite")!
  }

  func listCollectionIdsURL(parentPath: String?) throws -> URL {
    let base = documentsBaseURL
    let parent: String
    if let parentPath, !parentPath.isEmpty {
      parent = "\(base)/\(Self.percentEncodedPath(parentPath))"
    } else {
      parent = base
    }
    guard let url = URL(string: "\(parent):listCollectionIds") else {
      throw FirestoreParsingError.invalidDocumentData(
        "Could not build a URL for parent '\(parentPath ?? "root")'."
      )
    }
    return url
  }

  func fullDocumentPath(for relativePath: String) -> String {
    let trimmed = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return "projects/\(projectId)/databases/\(databaseId)/documents/\(trimmed)"
  }

  private static func normalizedBaseURL(_ value: String) -> String {
    value.hasSuffix("/") ? String(value.dropLast()) : value
  }

  /// Percent-encodes each path segment while keeping the separators intact.
  private static func percentEncodedPath(_ path: String) -> String {
    path
      .split(separator: "/", omittingEmptySubsequences: false)
      .map { percentEncodedComponent(String($0)) }
      .joined(separator: "/")
  }

  private static func percentEncodedComponent(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
  }
}
