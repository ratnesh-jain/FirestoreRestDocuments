import Crypto
import Foundation
#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
import _CryptoExtras

/// Decoded contents of a Google service account JSON key file.
public struct FirestoreServiceAccount: Codable, Sendable {
  public let type: String?
  public let projectId: String
  public let privateKeyId: String?
  public let privateKey: String
  public let clientEmail: String
  public let clientId: String?
  public let authUri: String?
  public let tokenUri: String

  enum CodingKeys: String, CodingKey {
    case type
    case projectId = "project_id"
    case privateKeyId = "private_key_id"
    case privateKey = "private_key"
    case clientEmail = "client_email"
    case clientId = "client_id"
    case authUri = "auth_uri"
    case tokenUri = "token_uri"
  }

  public init(
    type: String? = nil,
    projectId: String,
    privateKeyId: String? = nil,
    privateKey: String,
    clientEmail: String,
    clientId: String? = nil,
    authUri: String? = nil,
    tokenUri: String = "https://oauth2.googleapis.com/token"
  ) {
    self.type = type
    self.projectId = projectId
    self.privateKeyId = privateKeyId
    self.privateKey = privateKey
    self.clientEmail = clientEmail
    self.clientId = clientId
    self.authUri = authUri
    self.tokenUri = tokenUri
  }
}

/// Mints and caches OAuth2 access tokens from a Google service account key.
public actor ServiceAccountTokenProvider: FirestoreAccessTokenProvider {
  private let serviceAccount: FirestoreServiceAccount
  private let scopes: [String]

  private var cachedToken: String?
  private var expiry: Date?

  public init(
    serviceAccount: FirestoreServiceAccount,
    scopes: [String] = ["https://www.googleapis.com/auth/datastore"]
  ) {
    self.serviceAccount = serviceAccount
    self.scopes = scopes
  }

  public init(
    keyData: Data,
    scopes: [String] = ["https://www.googleapis.com/auth/datastore"]
  ) throws {
    let account = try JSONDecoder().decode(FirestoreServiceAccount.self, from: keyData)
    self.init(serviceAccount: account, scopes: scopes)
  }

  public init(
    keyFileAtPath path: String,
    scopes: [String] = ["https://www.googleapis.com/auth/datastore"]
  ) throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    try self.init(keyData: data, scopes: scopes)
  }

  public func accessToken() async throws -> String {
    if let cachedToken, let expiry, Date() < expiry.addingTimeInterval(-60) {
      return cachedToken
    }
    let response = try await mintToken()
    cachedToken = response.accessToken
    expiry = Date().addingTimeInterval(TimeInterval(response.expiresIn))
    return response.accessToken
  }

  private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case expiresIn = "expires_in"
      case tokenType = "token_type"
    }
  }

  private func mintToken() async throws -> TokenResponse {
    let now = Int(Date().timeIntervalSince1970)
    var header: [String: Any] = ["alg": "RS256", "typ": "JWT"]
    if let kid = serviceAccount.privateKeyId {
      header["kid"] = kid
    }
    let claims: [String: Any] = [
      "iss": serviceAccount.clientEmail,
      "scope": scopes.joined(separator: " "),
      "aud": serviceAccount.tokenUri,
      "iat": now,
      "exp": now + 3600
    ]

    let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
    let claimsData = try JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
    let signingInput = "\(base64URLEncode(headerData)).\(base64URLEncode(claimsData))"

    let privateKey = try _RSA.Signing.PrivateKey(pemRepresentation: serviceAccount.privateKey)
    let signature = try privateKey.signature(
      for: Data(signingInput.utf8),
      padding: .insecurePKCS1v1_5
    )
    let jwt = "\(signingInput).\(base64URLEncode(signature.rawRepresentation))"

    var request = URLRequest(url: URL(string: serviceAccount.tokenUri)!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let body = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
    request.httpBody = body.data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? "<empty>"
      throw FirestoreParsingError.decodingFailed("Token request failed: \(body)")
    }
    return try JSONDecoder().decode(TokenResponse.self, from: data)
  }

  private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
