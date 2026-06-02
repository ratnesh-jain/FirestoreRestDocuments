import Testing
import Foundation
@testable import FirestoreRestDocuments

// MARK: - Mock URLProtocol (thread-safe)

private let mockHandlerQueue = DispatchQueue(label: "mock-handler")
nonisolated(unsafe) private var _mockHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

private final class MockURLProtocol: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let handler = mockHandlerQueue.sync { _mockHandler }
    guard let handler else {
      fatalError("No mock handler set")
    }
    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}

  static func withHandler(
    _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data),
    operation: () async throws -> Void
  ) async throws {
    mockHandlerQueue.sync { _mockHandler = handler }
    URLProtocol.registerClass(self)
    defer {
      URLProtocol.unregisterClass(self)
      mockHandlerQueue.sync { _mockHandler = nil }
    }
    try await operation()
  }
}

// MARK: - Tests

@Suite("URL Construction")
struct URLConstructionTests {
  @Test func collection() throws {
    let config = FirestoreConfig(projectId: "my-project", databaseId: "(default)")
    let req = try config.makeRequest(path: "users")
    #expect(req.url!.absoluteString == "https://firestore.googleapis.com/v1/projects/my-project/databases/(default)/documents/users")
  }

  @Test func document() throws {
    let config = FirestoreConfig(projectId: "proj", databaseId: "db")
    let req = try config.makeRequest(path: "users/user123")
    #expect(req.url!.absoluteString == "https://firestore.googleapis.com/v1/projects/proj/databases/db/documents/users/user123")
  }

  @Test func nestedCollection() throws {
    let config = FirestoreConfig(projectId: "proj", databaseId: "db")
    let req = try config.makeRequest(path: "users/user123/orders")
    #expect(req.url!.absoluteString == "https://firestore.googleapis.com/v1/projects/proj/databases/db/documents/users/user123/orders")
  }
}

@Suite("Authentication")
struct AuthTests {
  @Test func bearerToken() throws {
    let config = FirestoreConfig(projectId: "p", accessToken: "my-token")
    let req = try config.makeRequest(path: "users")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")
  }

  @Test func apiKey() throws {
    let config = FirestoreConfig(projectId: "p", apiKey: "my-key")
    let req = try config.makeRequest(path: "users")
    #expect(req.url!.absoluteString.contains("key=my-key"))
  }

  @Test func bearerTakesPriority() throws {
    let config = FirestoreConfig(projectId: "p", accessToken: "bearer", apiKey: "key")
    let req = try config.makeRequest(path: "users")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer bearer")
    #expect(!req.url!.absoluteString.contains("key="))
  }
}

@Suite("Network calls", .serialized)
struct NetworkTests {

  private let singleDocJSON = """
  {
    "name": "projects/p/databases/d/documents/users/user1",
    "fields": {
      "name": {"stringValue": "Alice"},
      "email": {"stringValue": "alice@example.com"}
    }
  }
  """.data(using: .utf8)!

  private let listJSON = """
  {
    "documents": [
      {"fields": {"name": {"stringValue": "Alice"}}},
      {"fields": {"name": {"stringValue": "Bob"}}}
    ]
  }
  """.data(using: .utf8)!

  struct User: Decodable { let name: String; let email: String? }
  struct SimpleUser: Decodable { let name: String }

  @Test func fetchSingleDocument() async throws {
    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.singleDocJSON)
    }) {
      let config = FirestoreConfig(projectId: "p", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let user = try await db.decode(User.self, from: "users/user1")
      #expect(user.name == "Alice")
      #expect(user.email == "alice@example.com")
    }
  }

  @Test func fetchList() async throws {
    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.listJSON)
    }) {
      let config = FirestoreConfig(projectId: "p", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let users = try await db.decode([SimpleUser].self, from: "users")
      #expect(users.count == 2)
      #expect(users[0].name == "Alice")
      #expect(users[1].name == "Bob")
    }
  }

  @Test func httpError() async throws {
    try await MockURLProtocol.withHandler({ request in
      let body = #"{"error": {"message": "Permission denied"}}"#.data(using: .utf8)!
      return (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, body)
    }) {
      let config = FirestoreConfig(projectId: "p", accessToken: "bad")
      let db = FirestoreDocument(config: config)
      await #expect(throws: FirestoreParsingError.self) {
        let _: User = try await db.decode(User.self, from: "users/user1")
      }
    }
  }

  @Test func fetchPage() async throws {
    let page1JSON = """
    {
      "nextPageToken": "token2",
      "documents": [
        {"name": "p/d/doc/users/u1", "fields": {"name": {"stringValue": "Alice"}}},
        {"name": "p/d/doc/users/u2", "fields": {"name": {"stringValue": "Bob"}}}
      ]
    }
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      let url = request.url!.absoluteString
      #expect(url.contains("pageSize=10"))
      #expect(!url.contains("pageToken"))
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, page1JSON)
    }) {
      let config = FirestoreConfig(projectId: "p", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let page = try await db.fetchPage(SimpleUser.self, from: "users", pageSize: 10)
      #expect(page.items.count == 2)
      #expect(page.nextPageToken == "token2")
      #expect(page.items[0].name == "Alice")
      #expect(page.items[1].name == "Bob")
    }
  }

  @Test func fetchPageWithToken() async throws {
    let page2JSON = """
    {
      "documents": [
        {"name": "p/d/doc/users/u3", "fields": {"name": {"stringValue": "Charlie"}}}
      ]
    }
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      let url = request.url!.absoluteString
      #expect(url.contains("pageToken=token2"))
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, page2JSON)
    }) {
      let config = FirestoreConfig(projectId: "p", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let page = try await db.fetchPage(SimpleUser.self, from: "users", pageSize: 10, pageToken: "token2")
      #expect(page.items.count == 1)
      #expect(page.nextPageToken == nil)
      #expect(page.items[0].name == "Charlie")
    }
  }

  @Test func staticDecode() async throws {
    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.singleDocJSON)
    }) {
      FirestoreConfig.shared = FirestoreConfig(projectId: "p", accessToken: "tok")
      let user = try await FirestoreDocument.decode(User.self, from: "users/user1")
      #expect(user.name == "Alice")
    }
  }

  @Test func usingJSONDecoder() async throws {
    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.singleDocJSON)
    }) {
      let config = FirestoreConfig(projectId: "p", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let decoder = JSONDecoder()
      let user = try await db.decode(User.self, from: "users/user1", using: decoder)
      #expect(user.name == "Alice")
    }
  }
}
