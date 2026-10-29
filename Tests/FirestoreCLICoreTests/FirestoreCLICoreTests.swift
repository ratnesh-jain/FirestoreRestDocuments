import Foundation
import Testing
@testable import FirestoreCLICore
import FirestoreRestDocuments

private func makeConfig() -> FirestoreConfig {
  FirestoreConfig(projectId: "test-project", databaseId: "(default)", accessToken: "token")
}

private func wrapper(_ fields: [String: Any], _ key: String) throws -> [String: Any] {
  try #require(fields[key] as? [String: Any])
}

@Suite("Path handling")
struct FirestorePathTests {
  @Test func normalizesSlashes() throws {
    #expect(try FirestorePath.document("/users/alice/") == "users/alice")
    #expect(try FirestorePath.collection("/users/alice/orders/") == "users/alice/orders")
  }

  @Test func rejectsEmptySegments() {
    #expect(throws: CLIError.self) {
      try FirestorePath.document("users//alice")
    }
  }

  @Test func rejectsCollectionForDocument() {
    #expect(throws: CLIError.self) {
      try FirestorePath.document("users")
    }
  }

  @Test func rejectsDocumentForCollection() {
    #expect(throws: CLIError.self) {
      try FirestorePath.collection("users/alice")
    }
  }

  @Test func resolvesWriteTarget() throws {
    #expect(try FirestorePath.writeTarget("users/alice", id: nil, generateID: true) == "users/alice")
    #expect(try FirestorePath.writeTarget("users", id: "alice", generateID: true) == "users/alice")
  }

  @Test func generatesIDForCollection() throws {
    let path = try FirestorePath.writeTarget("users", id: nil, generateID: true)
    #expect(path.hasPrefix("users/"))
    let id = String(path.dropFirst("users/".count))
    #expect(id.count == 20)
  }

  @Test func rejectsIDForDocument() {
    #expect(throws: CLIError.self) {
      try FirestorePath.writeTarget("users/alice", id: "bob", generateID: true)
    }
  }

  @Test func parsesMask() throws {
    #expect(try FirestorePath.parseMask("name, email ,,") == ["name", "email"])
  }

  @Test func extractsDocumentID() {
    #expect(
      FirestorePath.documentID(fromFullName: "projects/p/databases/d/documents/users/alice")
        == "alice"
    )
  }

  @Test func resolvesCollectionParent() throws {
    #expect(try FirestorePath.parentDocument(nil) == nil)
    #expect(try FirestorePath.parentDocument("  ") == nil)
    #expect(try FirestorePath.parentDocument("/users/alice/") == "users/alice")
    #expect(throws: CLIError.self) {
      try FirestorePath.parentDocument("users")
    }
  }
}

@Suite("Pagination")
struct PageSizingTests {
  @Test func usesRequestedPageSize() {
    #expect(PageSizing.size(requested: 25, limit: nil, alreadyFetched: 0, followAll: false) == 25)
  }

  @Test func usesServerDefaultForSinglePage() {
    #expect(PageSizing.size(requested: nil, limit: nil, alreadyFetched: 0, followAll: false) == nil)
  }

  @Test func usesLargePageWhenFollowingAll() {
    #expect(PageSizing.size(requested: nil, limit: nil, alreadyFetched: 50, followAll: true) == 1000)
  }

  @Test func capsPageSizeAtRemainingLimit() {
    #expect(PageSizing.size(requested: nil, limit: 10, alreadyFetched: 3, followAll: false) == 7)
    #expect(PageSizing.size(requested: nil, limit: 10, alreadyFetched: 10, followAll: false) == 1)
  }
}

@Suite("Document payload")
struct DocumentPayloadTests {
  @Test func convertsFlatJSONToWireFormat() throws {
    let json: [String: Any] = [
      "name": "Alice",
      "age": 30,
      "score": 9.5,
      "active": true,
      "nickname": NSNull(),
      "tags": ["a", "b"],
      "address": ["city": "NYC"],
    ]
    let fields = try DocumentPayload.fields(fromJSON: json, config: makeConfig())

    #expect(try wrapper(fields, "name")["stringValue"] as? String == "Alice")
    #expect(try wrapper(fields, "age")["integerValue"] as? String == "30")
    #expect(try wrapper(fields, "score")["doubleValue"] as? Double == 9.5)
    #expect(try wrapper(fields, "active")["booleanValue"] as? Bool == true)
    #expect(try wrapper(fields, "nickname")["nullValue"] is NSNull)

    let tags = try wrapper(try wrapper(fields, "tags"), "arrayValue")
    let values = try #require(tags["values"] as? [[String: Any]])
    #expect(values.count == 2)
    #expect(values[0]["stringValue"] as? String == "a")

    let address = try wrapper(try wrapper(fields, "address"), "mapValue")
    let addressFields = try #require(address["fields"] as? [String: Any])
    #expect(try wrapper(addressFields, "city")["stringValue"] as? String == "NYC")
  }

  @Test func convertsDoubleThatLooksLikeInteger() throws {
    let json: [String: Any] = ["whole": 1.0]
    let fields = try DocumentPayload.fields(fromJSON: json, config: makeConfig())
    #expect(try wrapper(fields, "whole")["doubleValue"] as? Double == 1.0)
    #expect(try wrapper(fields, "whole")["integerValue"] == nil)
  }

  @Test func convertsTypedValueTags() throws {
    let json: [String: Any] = [
      "created": ["$timestamp": "2024-06-15T10:30:00Z"],
      "ref": ["$reference": "users/u2"],
      "location": ["$geopoint": ["latitude": 37.77, "longitude": -122.42]],
      "blob": ["$bytes": "SGVsbG8="],
      "integer": ["$integer": "42"],
      "double": ["$double": "1.5"],
      "literal": ["$literal": ["$timestamp": "not-a-tag"]],
    ]
    let fields = try DocumentPayload.fields(fromJSON: json, config: makeConfig())

    #expect(try wrapper(fields, "created")["timestampValue"] as? String == "2024-06-15T10:30:00Z")
    #expect(
      try wrapper(fields, "ref")["referenceValue"] as? String
        == "projects/test-project/databases/(default)/documents/users/u2"
    )
    #expect(try wrapper(try wrapper(fields, "location"), "geoPointValue")["latitude"] as? Double == 37.77)
    #expect(try wrapper(fields, "blob")["bytesValue"] as? String == "SGVsbG8=")
    #expect(try wrapper(fields, "integer")["integerValue"] as? String == "42")
    #expect(try wrapper(fields, "double")["doubleValue"] as? Double == 1.5)

    let literal = try wrapper(try wrapper(fields, "literal"), "mapValue")
    let literalFields = try #require(literal["fields"] as? [String: Any])
    #expect(try wrapper(literalFields, "$timestamp")["stringValue"] as? String == "not-a-tag")
  }

  @Test func rejectsUnknownTags() {
    #expect(throws: CLIError.self) {
      try DocumentPayload.fields(fromJSON: ["bad": ["$nope": "x"]], config: makeConfig())
    }
  }

  @Test func rejectsInvalidTimestamp() {
    #expect(throws: CLIError.self) {
      try DocumentPayload.fields(
        fromJSON: ["when": ["$timestamp": "yesterday"]],
        config: makeConfig()
      )
    }
  }

  @Test func acceptsWireDocument() throws {
    let wire = """
    {
      "name": "projects/p/databases/d/documents/users/u1",
      "fields": {
        "age": {"integerValue": "30"},
        "address": {"mapValue": {"fields": {"city": {"stringValue": "NYC"}}}}
      }
    }
    """.data(using: .utf8)!

    let fields = try DocumentPayload.fields(from: wire, config: makeConfig())
    #expect(try wrapper(fields, "age")["integerValue"] as? String == "30")
  }

  @Test func flatDocumentWithFieldsKeyIsNotMistakenForWireFormat() throws {
    let json: [String: Any] = ["fields": ["a": 1]]
    let fields = try DocumentPayload.fields(fromJSON: json, config: makeConfig())
    #expect(fields["a"] == nil)
    let map = try wrapper(try wrapper(fields, "fields"), "mapValue")
    let mapFields = try #require(map["fields"] as? [String: Any])
    #expect(try wrapper(mapFields, "a")["integerValue"] as? String == "1")
  }

  @Test func normalizesFieldsForDisplay() throws {
    let normalized = try DocumentPayload.normalizedFields([
      "name": ["stringValue": "Alice"],
      "age": ["integerValue": "30"],
    ])
    #expect(normalized["name"] as? String == "Alice")
    #expect((normalized["age"] as? NSNumber)?.intValue == 30)
  }

  @Test func flattensFirestoreValues() {
    let value = FirestoreValue.document(name: "users/u1", fields: [
      "name": .string("Alice"),
      "age": .int(30),
      "score": .double(9.5),
      "tags": .array([.string("a"), .string("b")]),
      "location": .geoPoint(latitude: 1, longitude: 2),
    ])
    let flat = try! #require(DocumentPayload.flatValue(value) as? [String: Any])
    #expect(flat["name"] as? String == "Alice")
    #expect(flat["age"] as? Int64 == 30)
    #expect(flat["score"] as? Double == 9.5)
    #expect((flat["tags"] as? [Any])?.count == 2)
    #expect((flat["location"] as? [String: Any])?["latitude"] as? Double == 1)
  }
}

@Suite("Batch file parsing")
struct BatchWriteFileTests {
  @Test func parsesOperations() throws {
    let data = """
    [
      {"op": "create", "path": "users/u1", "data": {"name": "Alice"}},
      {"op": "update", "path": "users/u1", "data": {"name": "Bob"}},
      {"op": "set", "path": "users/u2", "data": {"name": "Carol"}, "mask": "name"},
      {"op": "delete", "path": "users/u3"}
    ]
    """.data(using: .utf8)!

    let json = try JSONParsing.any(from: data)
    let writes = try BatchWriteFile.writes(from: json, config: makeConfig())
    #expect(writes.count == 4)
    #expect(writes.map(\.documentPath) == ["users/u1", "users/u1", "users/u2", "users/u3"])

    if case .create = writes[0].storage {} else {
      Issue.record("First write should be a create")
    }
    if case .update(_, let mask, _) = writes[1].storage {
      #expect(mask == ["name"])
    } else {
      Issue.record("Second write should be an update")
    }
    if case .update(_, let mask, _) = writes[2].storage {
      #expect(mask == ["name"])
    } else {
      Issue.record("Third write should be an update")
    }
    if case .delete = writes[3].storage {} else {
      Issue.record("Fourth write should be a delete")
    }
  }

  @Test func acceptsWritesWrapper() throws {
    let data = #"{"writes": [{"op": "delete", "path": "users/u1"}]}"#.data(using: .utf8)!
    let json = try JSONParsing.any(from: data)
    #expect(try BatchWriteFile.writes(from: json, config: makeConfig()).count == 1)
  }

  @Test func rejectsUnknownOperation() throws {
    let data = #"[{"op": "upsert", "path": "users/u1", "data": {}}]"#.data(using: .utf8)!
    let json = try JSONParsing.any(from: data)
    #expect(throws: CLIError.self) {
      try BatchWriteFile.writes(from: json, config: makeConfig())
    }
  }

  @Test func rejectsCollectionPath() throws {
    let data = #"[{"op": "delete", "path": "users"}]"#.data(using: .utf8)!
    let json = try JSONParsing.any(from: data)
    #expect(throws: CLIError.self) {
      try BatchWriteFile.writes(from: json, config: makeConfig())
    }
  }
}

@Suite("Connection resolution")
struct ConnectionResolutionTests {
  @Test func readsProjectAndTokenFromEnvironment() throws {
    let options = try GlobalOptions.parse([])
    let resolved = try options.resolveConnection(environment: [
      "FIRESTORE_PROJECT_ID": "env-project",
      "FIRESTORE_ACCESS_TOKEN": "env-token",
      "FIRESTORE_DATABASE_ID": "env-db",
    ])
    #expect(resolved.config.projectId == "env-project")
    #expect(resolved.config.databaseId == "env-db")
    #expect(resolved.config.accessToken == "env-token")
    #expect(resolved.config.baseURL == FirestoreConfig.defaultBaseURL)
  }

  @Test func flagsTakePrecedenceOverEnvironment() throws {
    let options = try GlobalOptions.parse([
      "--project", "flag-project",
      "--database", "flag-db",
      "--token", "flag-token",
    ])
    let resolved = try options.resolveConnection(environment: [
      "FIRESTORE_PROJECT_ID": "env-project",
      "FIRESTORE_ACCESS_TOKEN": "env-token",
    ])
    #expect(resolved.config.projectId == "flag-project")
    #expect(resolved.config.databaseId == "flag-db")
    #expect(resolved.config.accessToken == "flag-token")
  }

  @Test func emulatorUsesLocalURLAndOwnerToken() throws {
    let options = try GlobalOptions.parse(["--project", "p", "--emulator-host", "localhost:8080"])
    let resolved = try options.resolveConnection(environment: [:])
    #expect(resolved.config.baseURL == "http://localhost:8080/v1")
    #expect(resolved.config.accessToken == "owner")
  }

  @Test func emulatorEnvironmentVariable() throws {
    let options = try GlobalOptions.parse(["--project", "p"])
    let resolved = try options.resolveConnection(environment: [
      "FIRESTORE_EMULATOR_HOST": "127.0.0.1:9000"
    ])
    #expect(resolved.config.baseURL == "http://127.0.0.1:9000/v1")
  }

  @Test func missingProjectThrows() {
    let options = try! GlobalOptions.parse(["--token", "t"])
    #expect(throws: CLIError.self) {
      try options.resolveConnection(environment: [:])
    }
  }

  @Test func missingCredentialsThrows() {
    let options = try! GlobalOptions.parse(["--project", "p"])
    #expect(throws: CLIError.self) {
      try options.resolveConnection(environment: [:])
    }
  }

  @Test func dryRunDoesNotRequireCredentials() throws {
    let options = try! GlobalOptions.parse(["--project", "p"])
    let resolved = try options.resolveConnection(requiresCredentials: false, environment: [:])
    #expect(resolved.config.projectId == "p")
    #expect(resolved.config.accessToken == "dry-run")
  }

  @Test func dryRunStillRequiresProject() {
    let options = try! GlobalOptions.parse([])
    #expect(throws: CLIError.self) {
      try options.resolveConnection(requiresCredentials: false, environment: [:])
    }
  }

  @Test func apiKeyOnlyIsAllowed() throws {
    let options = try GlobalOptions.parse(["--project", "p", "--api-key", "key"])
    let resolved = try options.resolveConnection(environment: [:])
    #expect(resolved.config.apiKey == "key")
    #expect(resolved.config.accessToken == nil)
  }

  @Test func serviceAccountProvidesProjectFallback() throws {
    let path = try makeServiceAccountFile(projectId: "sa-project")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let options = try GlobalOptions.parse([])
    let resolved = try options.resolveConnection(environment: [
      "GOOGLE_APPLICATION_CREDENTIALS": path
    ])
    #expect(resolved.config.projectId == "sa-project")
    #expect(resolved.config.accessToken == nil)
  }

  @Test func accessTokenTakesPrecedenceOverServiceAccount() throws {
    let path = try makeServiceAccountFile(projectId: "sa-project")
    defer { try? FileManager.default.removeItem(atPath: path) }

    let options = try GlobalOptions.parse([])
    let resolved = try options.resolveConnection(environment: [
      "GOOGLE_APPLICATION_CREDENTIALS": path,
      "FIRESTORE_ACCESS_TOKEN": "env-token",
      "FIRESTORE_PROJECT_ID": "env-project",
    ])
    #expect(resolved.config.projectId == "env-project")
    #expect(resolved.config.accessToken == "env-token")
  }

  private func makeServiceAccountFile(projectId: String) throws -> String {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("frd-sa-\(UUID().uuidString).json")
      .path
    let json = """
    {
      "type": "service_account",
      "project_id": "\(projectId)",
      "private_key": "not-a-real-key",
      "client_email": "test@example.com",
      "token_uri": "https://oauth2.googleapis.com/token"
    }
    """
    try json.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
    return path
  }
}
