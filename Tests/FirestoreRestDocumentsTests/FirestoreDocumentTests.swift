import Testing
import Foundation
@testable import FirestoreRestDocuments

// MARK: - Mock URLProtocol (thread-safe, shared across test files)

let mockHandlerQueue = DispatchQueue(label: "mock-handler")
nonisolated(unsafe) var _mockHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

final class MockURLProtocol: URLProtocol {
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

  // MARK: Batch operations

  private let user1JSON = """
    {"name": "projects/p/d/documents/users/u1", "fields": {"name": {"stringValue": "Alice"}}, "createTime": "2024-01-01T00:00:00Z", "updateTime": "2024-01-01T00:00:00Z"}
    """

  private let user2JSON = """
    {"name": "projects/p/d/documents/users/u2", "fields": {"name": {"stringValue": "Bob"}}, "createTime": "2024-01-01T00:00:00Z", "updateTime": "2024-01-01T00:00:00Z"}
    """

  private let userJSON = """
    {"name": "projects/p/d/documents/users/u1", "fields": {"name": {"stringValue": "Alice"}}, "createTime": "2024-01-01T00:00:00Z", "updateTime": "2024-01-01T00:00:00Z"}
    """

  private let postJSON = """
    {"name": "projects/p/d/documents/posts/p1", "fields": {"title": {"stringValue": "Hello"}}, "createTime": "2024-01-01T00:00:00Z", "updateTime": "2024-01-01T00:00:00Z"}
    """

  struct BatchUser: Decodable, Sendable { let name: String }
  struct Post: Decodable, Sendable { let title: String }

  @Test func batchGetLowLevel() async throws {
    let batchGetResponse = """
    [
      {"found": \(user1JSON), "readTime": "2024-01-01T00:00:00Z"},
      {"found": \(user2JSON), "readTime": "2024-01-01T00:00:00Z"}
    ]
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.absoluteString.hasSuffix(":batchGet"))
      #expect(request.httpMethod == "POST")
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchGetResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let results = try await db.batchGet(documents: ["users/u1", "users/u2"])
      #expect(results.count == 2)
      #expect(results[0].isFound)
      #expect(results[1].isFound)
    }
  }

  @Test func batchGetWithMask() async throws {
    let batchGetResponse = """
    [
      {"found": \(user1JSON), "readTime": "2024-01-01T00:00:00Z"}
    ]
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.absoluteString.hasSuffix(":batchGet"))
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchGetResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let results = try await db.batchGet(documents: ["users/u1"], mask: FirestoreDocumentMask(fieldPaths: ["name"]))
      #expect(results.count == 1)
    }
  }

  @Test func batchGetTypedDecodes() async throws {
    let batchGetResponse = """
    [
      {"found": \(user1JSON), "readTime": "2024-01-01T00:00:00Z"},
      {"found": \(user2JSON), "readTime": "2024-01-01T00:00:00Z"}
    ]
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchGetResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let users = try await db.batchGet(BatchUser.self, documents: ["users/u1", "users/u2"])
      #expect(users.count == 2)
      #expect(users[0].data.name == "Alice")
      #expect(users[1].data.name == "Bob")
    }
  }

  @Test func batchGetTypedSkipsMissing() async throws {
    let batchGetResponse = """
    [
      {"found": \(user1JSON), "readTime": "2024-01-01T00:00:00Z"},
      {"missing": "projects/p/d/documents/users/missing", "readTime": "2024-01-01T00:00:00Z"}
    ]
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchGetResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let users = try await db.batchGet(BatchUser.self, documents: ["users/u1", "users/missing"])
      #expect(users.count == 1)
      #expect(users[0].data.name == "Alice")
    }
  }

  @Test func commitSendsWrites() async throws {
    let commitResponse = """
    {"writeResults": [{"updateTime": "2024-01-01T00:00:00Z"}, {"updateTime": "2024-01-01T00:00:01Z"}], "commitTime": "2024-01-01T00:00:00Z"}
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.absoluteString.hasSuffix(":commit"))
      #expect(request.httpMethod == "POST")
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, commitResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let writes: [FirestoreWrite] = [
        .delete(at: "users/old"),
        .delete(at: "users/older"),
      ]
      let response = try await db.commit(writes: writes)
      #expect(response.writeResults.count == 2)
    }
  }

  @Test func commitWithTransaction() async throws {
    let commitResponse = """
    {"writeResults": [], "commitTime": "2024-01-01T00:00:00Z"}
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.absoluteString.hasSuffix(":commit"))
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, commitResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let response = try await db.commit(writes: [], transaction: "txn123")
      #expect(response.commitTime == "2024-01-01T00:00:00Z")
    }
  }

  @Test func batchWriteSendsRequest() async throws {
    let batchWriteResponse = """
    {"writeResults": [{"updateTime": "2024-01-01T00:00:00Z"}], "status": [{}]}
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.absoluteString.hasSuffix(":batchWrite"))
      #expect(request.httpMethod == "POST")
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchWriteResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let response = try await db.batchWrite(writes: [.delete(at: "users/u1")])
      #expect(response.writeResults.count == 1)
    }
  }

  @Test func batchWriteWithLabels() async throws {
    let batchWriteResponse = """
    {"writeResults": [], "status": []}
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.absoluteString.hasSuffix(":batchWrite"))
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchWriteResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)
      let response = try await db.batchWrite(writes: [], labels: ["env": "test"])
      #expect(response.writeResults.isEmpty)
    }
  }

  @Test func batchGetHTTPError() async throws {
    let errorBody = #"{"error": {"code": 403, "message": "Permission denied"}}"#.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!, errorBody)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "bad")
      let db = FirestoreDocument(config: config)
      await #expect(throws: FirestoreParsingError.self) {
        try await db.batchGet(documents: ["users/u1"])
      }
    }
  }

  @Test func multiTypeBatchGet() async throws {
    let batchGetResponse = """
    [
      {"found": \(userJSON), "readTime": "2024-01-01T00:00:00Z"},
      {"found": \(postJSON), "readTime": "2024-01-01T00:00:00Z"}
    ]
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchGetResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)

      let (users, posts) = try await db.batchGet(
        BatchUser.self, documentPaths: ["users/u1"],
        Post.self, documentPaths: ["posts/p1"]
      )
      #expect(users.count == 1)
      #expect(users[0].data.name == "Alice")
      #expect(posts.count == 1)
      #expect(posts[0].data.title == "Hello")
    }
  }

  @Test func multiTypeBatchGetSkipsMissing() async throws {
    let batchGetResponse = """
    [
      {"missing": "projects/p/d/documents/users/u1", "readTime": "2024-01-01T00:00:00Z"},
      {"found": \(postJSON), "readTime": "2024-01-01T00:00:00Z"}
    ]
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchGetResponse)
    }) {
      let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let db = FirestoreDocument(config: config)

      let (users, posts) = try await db.batchGet(
        BatchUser.self, documentPaths: ["users/u1"],
        Post.self, documentPaths: ["posts/p1"]
      )
      #expect(users.isEmpty)
      #expect(posts.count == 1)
    }
  }

  @Test func staticBatchGet() async throws {
    let batchGetResponse = """
    [
      {"found": {"name": "projects/p/d/documents/users/u1", "fields": {"name": {"stringValue": "Static"}}, "createTime": "2024-01-01T00:00:00Z", "updateTime": "2024-01-01T00:00:00Z"}, "readTime": "2024-01-01T00:00:00Z"}
    ]
    """.data(using: .utf8)!

    try await MockURLProtocol.withHandler({ request in
      (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, batchGetResponse)
    }) {
      FirestoreConfig.shared = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")
      let results = try await FirestoreDocument.batchGet(documents: ["users/u1"])
      #expect(results.count == 1)
      #expect(results[0].isFound)
    }
  }

  @Test func batchApplyAlias() async throws {
    let mockData = """
    {"writeResults": [], "commitTime": "2024-01-01T00:00:00Z"}
    """.data(using: .utf8)!
    let config = FirestoreConfig(projectId: "p", databaseId: "d", accessToken: "tok")

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.absoluteString.hasSuffix(":commit"))
      #expect(request.httpMethod == "POST")
      return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, mockData)
    }) {
      var batch = FirestoreBatch()
      batch.delete(at: "users/old")
      let db = FirestoreDocument(config: config)
      let response = try await batch.apply(to: db)
      #expect(response.commitTime == "2024-01-01T00:00:00Z")
    }
  }
}
