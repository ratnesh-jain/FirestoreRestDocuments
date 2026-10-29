import Foundation

/// Provides an access token for authenticating Firestore REST requests.
public protocol FirestoreAccessTokenProvider: Sendable {
  func accessToken() async throws -> String
}

/// A provider that always returns the same static token.
public struct StaticAccessTokenProvider: FirestoreAccessTokenProvider {
  public let token: String

  public init(token: String) {
    self.token = token
  }

  public func accessToken() async throws -> String {
    token
  }
}
