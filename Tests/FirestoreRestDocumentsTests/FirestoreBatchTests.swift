import Testing
import Foundation
@testable import FirestoreRestDocuments

// MARK: - BatchGet Result Parsing Tests

@Suite("FirestoreBatchGetResult parsing")
struct BatchGetResultParsingTests {

  @Test func decodeFound() throws {
    let json = """
    [
      {
        "found": {
          "name": "projects/p/databases/d/documents/users/user1",
          "fields": {
            "name": {"stringValue": "Alice"},
            "age": {"integerValue": "30"}
          },
          "createTime": "2024-01-01T00:00:00Z",
          "updateTime": "2024-01-02T00:00:00Z"
        },
        "readTime": "2024-01-02T00:00:00Z"
      }
    ]
    """.data(using: .utf8)!

    let parser = FirestoreDocumentParser()
    let results = try parser.decodeBatchGetResponse(from: json)
    #expect(results.count == 1)
    guard case .found(let doc) = results[0] else {
      Issue.record("Expected .found")
      return
    }
    #expect(doc.name == "projects/p/databases/d/documents/users/user1")
    #expect(doc.createTime == "2024-01-01T00:00:00Z")
    #expect(doc.updateTime == "2024-01-02T00:00:00Z")
    #expect(doc.fields["name"] == .string("Alice"))
    #expect(doc.fields["age"] == .int(30))
  }

  @Test func decodeMissing() throws {
    let json = """
    [
      {
        "missing": "projects/p/databases/d/documents/users/nonexistent",
        "readTime": "2024-01-01T00:00:00Z"
      }
    ]
    """.data(using: .utf8)!

    let parser = FirestoreDocumentParser()
    let results = try parser.decodeBatchGetResponse(from: json)
    #expect(results.count == 1)
    guard case .missing(let path) = results[0] else {
      Issue.record("Expected .missing")
      return
    }
    #expect(path == "projects/p/databases/d/documents/users/nonexistent")
  }

  @Test func decodeMixed() throws {
    let json = """
    [
      {
        "found": {
          "name": "projects/p/d/documents/users/u1",
          "fields": {"name": {"stringValue": "Alice"}}
        },
        "readTime": "2024-01-01T00:00:00Z"
      },
      {
        "missing": "projects/p/d/documents/users/u2",
        "readTime": "2024-01-01T00:00:00Z"
      }
    ]
    """.data(using: .utf8)!

    let parser = FirestoreDocumentParser()
    let results = try parser.decodeBatchGetResponse(from: json)
    #expect(results.count == 2)
    #expect(results[0].isFound)
    #expect(results[1].isMissing)
  }

  @Test func computedProperties() throws {
    let found = FirestoreBatchGetResult.found(FirestoreBatchFoundDocument(
      name: "projects/p/d/doc/users/u1", fields: [:], createTime: nil, updateTime: nil
    ))
    let missing = FirestoreBatchGetResult.missing("projects/p/d/doc/users/u2")

    #expect(found.isFound)
    #expect(!found.isMissing)
    #expect(found.documentName == "projects/p/d/doc/users/u1")

    #expect(!missing.isFound)
    #expect(missing.isMissing)
    #expect(missing.documentName == nil)
  }
}

// MARK: - Commit / BatchWrite Response Decoding Tests

@Suite("Commit and BatchWrite response decoding")
struct BatchResponseDecodingTests {

  @Test func decodeCommitResponse() throws {
    let json = """
    {
      "writeResults": [
        {"updateTime": "2024-01-01T00:00:00Z"},
        {"updateTime": "2024-01-01T00:00:01Z"}
      ],
      "commitTime": "2024-01-01T00:00:00Z"
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(FirestoreCommitResponse.self, from: json)
    #expect(response.writeResults.count == 2)
    #expect(response.writeResults[0].updateTime == "2024-01-01T00:00:00Z")
    #expect(response.commitTime == "2024-01-01T00:00:00Z")
  }

  @Test func decodeBatchWriteResponse() throws {
    let json = """
    {
      "writeResults": [
        {"updateTime": "2024-01-01T00:00:00Z"},
        {}
      ],
      "status": [
        {},
        {"code": 5, "message": "not found"}
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(FirestoreBatchWriteResponse.self, from: json)
    #expect(response.writeResults.count == 2)
    #expect(response.status?.count == 2)
    #expect(response.status?[1].code == 5)
    #expect(response.status?[1].message == "not found")
  }
}

// MARK: - FirestoreBatch Builder Tests

@Suite("FirestoreBatch builder")
struct FirestoreBatchBuilderTests {

  struct TestUser: Codable, Sendable {
    let name: String
    let age: Int
  }

  @Test func accumulatesWrites() throws {
    var batch = FirestoreBatch()
    try batch.create(TestUser(name: "Alice", age: 30), at: "users/new")
    batch.delete(at: "users/old")
    #expect(batch.count == 2)
  }

  @Test func emptyBatch() throws {
    let batch = FirestoreBatch()
    #expect(batch.count == 0)
  }

  @Test func accumulateAllTypes() throws {
    var batch = FirestoreBatch()
    try batch.create(TestUser(name: "Alice", age: 30), at: "users/new")
    try batch.update(TestUser(name: "Alice", age: 31), at: "users/existing", updateMask: ["age"])
    batch.delete(at: "users/old")
    #expect(batch.count == 3)
  }
}
