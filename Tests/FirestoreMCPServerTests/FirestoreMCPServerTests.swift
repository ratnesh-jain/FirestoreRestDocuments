import Foundation
import Testing
@testable import FirestoreMCPServer
import FirestoreOperations
import FirestoreRestDocuments
import MCP

// MARK: - Mock URLProtocol

private let mockHandlerQueue = DispatchQueue(label: "frd-mcp-mock-handler")
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

// MARK: - Helpers

private func makeConnection() -> ResolvedFirestoreConnection {
  ResolvedFirestoreConnection(
    config: FirestoreConfig(
      projectId: "demo",
      databaseId: "(default)",
      accessToken: "token"
    ),
    logLevel: .error
  )
}

private func makeDatabase() -> FirestoreDocument {
  FirestoreDocument(config: makeConnection().config, logLevel: .error)
}

private func ok(_ request: URLRequest, _ body: String) -> (HTTPURLResponse, Data) {
  (
    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
    Data(body.utf8)
  )
}

// MARK: - Tools

@Suite("MCP tools")
struct MCPToolsTests {
  @Test func exposesReadOnlyTools() {
    let tools = FirestoreTools.all
    #expect(Set(tools.map(\.name)) == [
      FirestoreTools.getDocument,
      FirestoreTools.listDocuments,
      FirestoreTools.listCollections,
    ])
    #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
    #expect(tools.allSatisfy { $0.annotations.openWorldHint == false })
  }

  @Test func listsToolsOverMCP() async throws {
    let server = await FirestoreMCPService.makeServer(connection: makeConnection())
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    try await server.start(transport: serverTransport)

    let client = Client(name: "frd-tests", version: "1.0.0")
    let initialized = try await client.connect(transport: clientTransport)
    #expect(initialized.capabilities.tools != nil)

    let (tools, _) = try await client.listTools()
    #expect(Set(tools.map(\.name)) == Set(FirestoreTools.all.map(\.name)))

    await client.disconnect()
    await server.stop()
  }
}

// MARK: - Handlers

@Suite("MCP tool handlers", .serialized)
struct MCPToolHandlerTests {
  @Test func getsDocumentWithMask() async throws {
    let body = """
    {
      "name": "projects/demo/databases/(default)/documents/users/alice",
      "fields": {"name": {"stringValue": "Alice"}},
      "createTime": "2024-01-01T00:00:00Z",
      "updateTime": "2024-01-02T00:00:00Z"
    }
    """

    try await MockURLProtocol.withHandler({ request in
      #expect(request.httpMethod == "GET")
      #expect(request.url!.query?.contains("mask.fieldPaths=name") == true)
      return ok(request, body)
    }) {
      let result = await FirestoreMCPService.callTool(
        name: FirestoreTools.getDocument,
        arguments: ["path": "users/alice", "mask": "name"],
        database: makeDatabase()
      )

      #expect(result.isError == false)
      let structured = try #require(result.structuredContent?.objectValue)
      #expect(structured["id"]?.stringValue == "alice")
      #expect(structured["path"]?.stringValue == "users/alice")
      #expect(structured["data"]?.objectValue?["name"]?.stringValue == "Alice")
    }
  }

  @Test func listsDocuments() async throws {
    let body = """
    {
      "documents": [
        {
          "name": "projects/demo/databases/(default)/documents/users/alice",
          "fields": {"name": {"stringValue": "Alice"}}
        },
        {
          "name": "projects/demo/databases/(default)/documents/users/bob",
          "fields": {"name": {"stringValue": "Bob"}}
        }
      ],
      "nextPageToken": "next"
    }
    """

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.query?.contains("pageSize=2") == true)
      return ok(request, body)
    }) {
      let result = await FirestoreMCPService.callTool(
        name: FirestoreTools.listDocuments,
        arguments: ["collection": "users", "pageSize": 2],
        database: makeDatabase()
      )

      #expect(result.isError == false)
      let structured = try #require(result.structuredContent?.objectValue)
      #expect(structured["collection"]?.stringValue == "users")
      #expect(structured["documents"]?.arrayValue?.count == 2)
      #expect(structured["nextPageToken"]?.stringValue == "next")
    }
  }

  @Test func listsRootCollections() async throws {
    let body = """
    {"collectionIds": ["users", "orders"]}
    """

    try await MockURLProtocol.withHandler({ request in
      #expect(request.httpMethod == "POST")
      #expect(request.url!.absoluteString.hasSuffix("/documents:listCollectionIds"))
      return ok(request, body)
    }) {
      let result = await FirestoreMCPService.callTool(
        name: FirestoreTools.listCollections,
        arguments: [:],
        database: makeDatabase()
      )

      #expect(result.isError == false)
      let structured = try #require(result.structuredContent?.objectValue)
      #expect(structured["collections"]?.arrayValue?.compactMap(\.stringValue) == ["users", "orders"])
      #expect(structured["parent"] == nil)
    }
  }

  @Test func listsSubcollections() async throws {
    let body = """
    {"collectionIds": ["orders"]}
    """

    try await MockURLProtocol.withHandler({ request in
      #expect(request.url!.absoluteString.hasSuffix("/documents/users/alice:listCollectionIds"))
      return ok(request, body)
    }) {
      let result = await FirestoreMCPService.callTool(
        name: FirestoreTools.listCollections,
        arguments: ["parent": "users/alice"],
        database: makeDatabase()
      )

      #expect(result.isError == false)
      let structured = try #require(result.structuredContent?.objectValue)
      #expect(
        structured["collections"]?.arrayValue?.compactMap(\.stringValue)
          == ["users/alice/orders"]
      )
      #expect(structured["parent"]?.stringValue == "users/alice")
    }
  }

  @Test func reportsMissingRequiredArgument() async {
    let result = await FirestoreMCPService.callTool(
      name: FirestoreTools.getDocument,
      arguments: [:],
      database: makeDatabase()
    )
    #expect(result.isError == true)
  }

  @Test func rejectsInvalidPageSize() async {
    let result = await FirestoreMCPService.callTool(
      name: FirestoreTools.listDocuments,
      arguments: ["collection": "users", "pageSize": 0],
      database: makeDatabase()
    )
    #expect(result.isError == true)
  }

  @Test func rejectsUnknownTool() async {
    let result = await FirestoreMCPService.callTool(
      name: "firestore_delete_everything",
      arguments: [:],
      database: makeDatabase()
    )
    #expect(result.isError == true)
  }
}
