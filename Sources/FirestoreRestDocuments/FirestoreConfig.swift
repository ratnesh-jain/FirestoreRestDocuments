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

  private static let defaultBaseURL = "https://firestore.googleapis.com/v1"

  nonisolated(unsafe) public static var shared = FirestoreConfig(projectId: "")

  public init(
    projectId: String,
    databaseId: String = "(default)",
    accessToken: String? = nil,
    apiKey: String? = nil
  ) {
    self.projectId = projectId
    self.databaseId = databaseId
    self.accessToken = accessToken
    self.apiKey = apiKey
  }

  var documentsBaseURL: String {
    "\(Self.defaultBaseURL)/projects/\(projectId)/databases/\(databaseId)/documents"
  }

  func makeRequest(path: String, queryItems: [URLQueryItem] = []) throws -> URLRequest {
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
    var url = URL(string: "\(documentsBaseURL)/\(path)")!
    var items = queryItems
    if let key = apiKey, accessToken == nil {
      items.append(URLQueryItem(name: "key", value: key))
    }
    if !items.isEmpty {
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw FirestoreParsingError.invalidDocumentData("Invalid URL")
      }
      components.queryItems = items
      url = components.url!
    }
    var req = URLRequest(url: url)
    Logger.firestoreRestDocuments.debug("Request URL: \(url.absoluteString)")
    if let token = accessToken {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return req
  }

  func makeRequest(url: URL) -> URLRequest {
    var req = URLRequest(url: url)
    if let token = accessToken {
      req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    return req
  }
}
