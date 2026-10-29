import Foundation
import Testing
@testable import FirestoreRestDocuments

@Suite("Write serialization")
struct WriteSerializationTests {
  private func config() -> FirestoreConfig {
    FirestoreConfig(projectId: "p", databaseId: "(default)", accessToken: "token")
  }

  private func writes(from body: Data) throws -> [[String: Any]] {
    let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
    return try #require(json["writes"] as? [[String: Any]])
  }

  private func fields(_ json: String) -> Data {
    json.data(using: .utf8)!
  }

  @Test func createUsesExistsFalsePrecondition() throws {
    let db = FirestoreDocument(config: config())
    let write = FirestoreWrite(
      documentPath: "users/u1",
      storage: .create(fieldsData: fields(#"{"name":{"stringValue":"Alice"}}"#))
    )

    let writeJSON = try #require(try writes(from: db.makeCommitBody(writes: [write])).first)
    #expect((writeJSON["currentDocument"] as? [String: Any])?["exists"] as? Bool == false)

    let update = try #require(writeJSON["update"] as? [String: Any])
    #expect(update["name"] as? String == "projects/p/databases/(default)/documents/users/u1")
    #expect(update["updateMask"] == nil)
    #expect(update["currentDocument"] == nil)
    #expect((update["fields"] as? [String: Any])?["name"] != nil)
  }

  @Test func updateMaskAndPreconditionAreSiblingsOfUpdate() throws {
    let db = FirestoreDocument(config: config())
    let write = FirestoreWrite(
      documentPath: "users/u1",
      storage: .update(
        fieldsData: fields(#"{"name":{"stringValue":"Alice"}}"#),
        updateMask: ["name"],
        exists: true
      )
    )

    let writeJSON = try #require(try writes(from: db.makeCommitBody(writes: [write])).first)
    #expect((writeJSON["updateMask"] as? [String: Any])?["fieldPaths"] as? [String] == ["name"])
    #expect((writeJSON["currentDocument"] as? [String: Any])?["exists"] as? Bool == true)

    let update = try #require(writeJSON["update"] as? [String: Any])
    #expect(update["updateMask"] == nil)
    #expect(update["currentDocument"] == nil)
  }

  @Test func updateWithoutMaskIsFullReplace() throws {
    let db = FirestoreDocument(config: config())
    let write = FirestoreWrite(
      documentPath: "users/u1",
      storage: .update(
        fieldsData: fields(#"{"name":{"stringValue":"Alice"}}"#),
        updateMask: nil,
        exists: nil
      )
    )

    let writeJSON = try #require(try writes(from: db.makeCommitBody(writes: [write])).first)
    #expect(writeJSON["updateMask"] == nil)
    #expect(writeJSON["currentDocument"] == nil)
    #expect(writeJSON["update"] != nil)
  }

  @Test func deleteUsesFullDocumentName() throws {
    let db = FirestoreDocument(config: config())
    let writeJSON = try #require(
      try writes(from: db.makeCommitBody(writes: [.delete(at: "users/u1")])).first
    )
    #expect(writeJSON["delete"] as? String == "projects/p/databases/(default)/documents/users/u1")
  }

  @Test func batchWriteIncludesLabels() throws {
    let db = FirestoreDocument(config: config())
    let write = FirestoreWrite(
      documentPath: "users/u1",
      storage: .update(
        fieldsData: fields(#"{"name":{"stringValue":"Alice"}}"#),
        updateMask: ["name"],
        exists: nil
      )
    )

    let body = try db.makeBatchWriteBody(writes: [write], labels: ["env": "test"])
    let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
    #expect((json["labels"] as? [String: String])?["env"] == "test")
    #expect((json["writes"] as? [Any])?.count == 1)
  }

  @Test func transactionIsIncludedInCommitBody() throws {
    let db = FirestoreDocument(config: config())
    let body = try db.makeCommitBody(writes: [.delete(at: "users/u1")], transaction: "abc")
    let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
    #expect(json["transaction"] as? String == "abc")
  }
}
