import Testing
import Foundation
@testable import FirestoreRestDocuments

struct FirebaseDocumentParserTests {

  @Test func testParseSimpleDocument() throws {
    let json = """
    {
      "name": "projects/test-project/databases/(default)/documents/users/user1",
      "fields": {
        "name": {"stringValue": "Alice"},
        "age": {"integerValue": "30"},
        "active": {"booleanValue": "true"},
        "score": {"doubleValue": 95.5}
      },
      "createTime": "2024-01-01T00:00:00Z",
      "updateTime": "2024-01-02T00:00:00Z"
    }
    """.data(using: .utf8)!

    let parser = FirestoreDocumentParser()

    struct User: Decodable {
      let name: String
      let age: Int64
      let active: Bool
      let score: Double
    }

    let user = try parser.decode(User.self, from: json)
    #expect(user.name == "Alice")
    #expect(user.age == 30)
    #expect(user.active == true)
    #expect(user.score == 95.5)
  }

  @Test func testParseWithNull() throws {
    let json = """
    {
      "fields": {
        "name": {"stringValue": "Bob"},
        "nickname": {"nullValue": null}
      }
    }
    """.data(using: .utf8)!

    let parser = FirestoreDocumentParser()
    struct User: Decodable {
      let name: String
      let nickname: String?
    }

    let user = try parser.decode(User.self, from: json)
    #expect(user.name == "Bob")
    #expect(user.nickname == nil)
  }

  @Test func testParseNestedMap() throws {
    let json = """
    {
      "fields": {
        "name": {"stringValue": "Charlie"},
        "address": {
          "mapValue": {
            "fields": {
              "city": {"stringValue": "NYC"},
              "zip": {"integerValue": "10001"}
            }
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct Address: Decodable {
      let city: String
      let zip: Int64
    }
    struct User: Decodable {
      let name: String
      let address: Address
    }

    let parser = FirestoreDocumentParser()
    let user = try parser.decode(User.self, from: json)
    #expect(user.name == "Charlie")
    #expect(user.address.city == "NYC")
    #expect(user.address.zip == 10001)
  }

  @Test func testParseArray() throws {
    let json = """
    {
      "fields": {
        "tags": {
          "arrayValue": {
            "values": [
              {"stringValue": "swift"},
              {"stringValue": "firebase"},
              {"stringValue": "ios"}
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct Post: Decodable {
      let tags: [String]
    }

    let parser = FirestoreDocumentParser()
    let post = try parser.decode(Post.self, from: json)
    #expect(post.tags == ["swift", "firebase", "ios"])
  }

  @Test func testParseTimestamp() throws {
    let json = """
    {
      "fields": {
        "createdAt": {"timestampValue": "2024-06-15T10:30:00.000Z"}
      }
    }
    """.data(using: .utf8)!

    struct Event: Decodable {
      let createdAt: Date
    }

    let parser = FirestoreDocumentParser()
    let event = try parser.decode(Event.self, from: json)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.createdAt)
    #expect(components.year == 2024)
    #expect(components.month == 6)
    #expect(components.day == 15)
    #expect(components.hour == 10)
    #expect(components.minute == 30)
  }

  @Test func testParseTimestampSecondsNanos() throws {
    let json = """
    {
      "fields": {
        "createdAt": {"timestampValue": {"seconds": "1718447400", "nanos": 500000000}}
      }
    }
    """.data(using: .utf8)!

    struct Event: Decodable {
      let createdAt: Date
    }

    let parser = FirestoreDocumentParser()
    let event = try parser.decode(Event.self, from: json)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: event.createdAt)
    #expect(components.year == 2024)
    #expect(components.month == 6)
    #expect(components.day == 15)
    #expect(components.hour == 10)
    #expect(components.minute == 30)
    #expect(components.second == 0)
  }

  @Test func testParseTimestampSecondsNanos_normalizer() throws {
    let json = """
    {
      "fields": {
        "createdAt": {"timestampValue": {"seconds": "1718447400", "nanos": 500000000}}
      }
    }
    """.data(using: .utf8)!

    let normalized = try FirestoreNormalizer.normalize(json)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    struct Event: Decodable {
      let createdAt: Date
    }

    let event = try decoder.firestoreDecode(Event.self, from: json)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.createdAt)
    #expect(components.year == 2024)
    #expect(components.month == 6)
    #expect(components.day == 15)
    #expect(components.hour == 10)
    #expect(components.minute == 30)
    #expect(components.second == 0)
  }

  @Test func testParseGeoPoint() throws {
    let json = """
    {
      "fields": {
        "location": {
          "geoPointValue": {
            "latitude": 37.7749,
            "longitude": -122.4194
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct Place: Decodable {
      let location: FirestoreGeoPoint
    }

    let parser = FirestoreDocumentParser()
    let place = try parser.decode(Place.self, from: json)
    #expect(place.location.latitude == 37.7749)
    #expect(place.location.longitude == -122.4194)
  }

  @Test func testParseDocumentReference() throws {
    let json = """
    {
      "fields": {
        "author": {"referenceValue": "projects/p/databases/d/documents/users/user1"}
      }
    }
    """.data(using: .utf8)!

    struct Book: Decodable {
      let author: String
    }

    let parser = FirestoreDocumentParser()
    let book = try parser.decode(Book.self, from: json)
    #expect(book.author == "projects/p/databases/d/documents/users/user1")
  }

  @Test func testParseBytes() throws {
    let data = "Hello".data(using: .utf8)!
    let base64 = data.base64EncodedString()
    let json = """
    {
      "fields": {
        "blob": {"bytesValue": "\(base64)"}
      }
    }
    """.data(using: .utf8)!

    struct File: Decodable {
      let blob: Data
    }

    let parser = FirestoreDocumentParser()
    let file = try parser.decode(File.self, from: json)
    #expect(String(data: file.blob, encoding: .utf8) == "Hello")
  }

  @Test func testEncodeSimpleDocument() throws {
    struct User: Encodable {
      let name: String
      let age: Int
      let active: Bool
    }

    let user = User(name: "Alice", age: 30, active: true)
    let parser = FirestoreDocumentParser()
    let data = try parser.encode(user, documentName: "users/alice")

    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(json["name"] as? String == "users/alice")
    let fields = json["fields"] as! [String: Any]

    let nameField = fields["name"] as! [String: String]
    #expect(nameField["stringValue"] == "Alice")

    let ageField = fields["age"] as! [String: String]
    #expect(ageField["integerValue"] == "30")

    let activeField = fields["active"] as! [String: String]
    #expect(activeField["booleanValue"] == "true")
  }

  @Test func testEncodeDecodeRoundTrip() throws {
    struct Person: Codable, Equatable {
      let name: String
      let age: Int
      let active: Bool
      let score: Double
      let tags: [String]
    }

    let original = Person(name: "Bob", age: 25, active: true, score: 88.5, tags: ["a", "b"])
    let parser = FirestoreDocumentParser()
    let data = try parser.encode(original, documentName: "people/bob")
    let decoded = try parser.decode(Person.self, from: data)
    #expect(original == decoded)
  }

  @Test func testDocumentIDPropertyWrapper() throws {
    let json = """
    {
      "name": "projects/p/databases/d/documents/users/user42",
      "fields": {
        "name": {"stringValue": "Alice"},
        "email": {"stringValue": "alice@example.com"}
      }
    }
    """.data(using: .utf8)!

    struct User: Decodable {
      @DocumentID var id: String?
      let name: String
      let email: String
    }

    let parser = FirestoreDocumentParser()
    let user = try parser.decode(User.self, from: json)
    #expect(user.id == "projects/p/databases/d/documents/users/user42")
    #expect(user.name == "Alice")
  }

  @Test func testServerTimestamp() throws {
    let json = """
    {
      "fields": {
        "name": {"stringValue": "Test"},
        "createdAt": {"timestampValue": "2024-06-15T10:30:00.000Z"}
      }
    }
    """.data(using: .utf8)!

    struct Item: Decodable {
      let name: String
      @ServerTimestamp var createdAt: Date?
    }

    let parser = FirestoreDocumentParser()
    let item = try parser.decode(Item.self, from: json)
    #expect(item.name == "Test")
    #expect(item.createdAt != nil)
  }

  @Test func testServerTimestampNull() throws {
    let json = """
    {
      "fields": {
        "name": {"stringValue": "Test"},
        "createdAt": {"nullValue": null}
      }
    }
    """.data(using: .utf8)!

    struct Item: Decodable {
      let name: String
      @ServerTimestamp var createdAt: Date?
    }

    let parser = FirestoreDocumentParser()
    let item = try parser.decode(Item.self, from: json)
    #expect(item.createdAt == nil)
  }

  @Test func testParseListDocuments() throws {
    let json = """
    {
      "documents": [
        {
          "name": "projects/p/databases/d/documents/users/user1",
          "fields": {
            "name": {"stringValue": "Alice"}
          }
        },
        {
          "name": "projects/p/databases/d/documents/users/user2",
          "fields": {
            "name": {"stringValue": "Bob"}
          }
        }
      ]
    }
    """.data(using: .utf8)!

    struct User: Decodable {
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let users = try parser.decode([User].self, from: json)
    #expect(users.count == 2)
    #expect(users[0].name == "Alice")
    #expect(users[1].name == "Bob")
  }

  @Test func testParseArrayOfDocumentsDirectly() throws {
    let json = """
    [
      {
        "name": "projects/p/databases/d/documents/users/user1",
        "fields": {
          "name": {"stringValue": "Alice"}
        }
      },
      {
        "name": "projects/p/databases/d/documents/users/user2",
        "fields": {
          "name": {"stringValue": "Bob"}
        }
      }
    ]
    """.data(using: .utf8)!

    struct User: Decodable {
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let users = try parser.decode([User].self, from: json)
    #expect(users.count == 2)
    #expect(users[0].name == "Alice")
    #expect(users[1].name == "Bob")
  }

  @Test func testParseEmptyFields() throws {
    let json = """
    {
      "name": "projects/p/databases/d/documents/empty/doc",
      "fields": {}
    }
    """.data(using: .utf8)!

    struct EmptyDoc: Decodable {}

    let parser = FirestoreDocumentParser()
    let _ = try parser.decode(EmptyDoc.self, from: json)
    // Should succeed with empty fields
  }

  @Test func testParseEmptyObjectField() throws {
    let json = """
    {
      "fields": {
        "metadata": {}
      }
    }
    """.data(using: .utf8)!

    struct Doc: Decodable {
      let metadata: [String: String]?
    }

    let parser = FirestoreDocumentParser()
    let doc = try parser.decode(Doc.self, from: json)
    #expect(doc.metadata == [:])
  }

  @Test func testEncodeWithServerTimestamp() throws {
    struct Item: Encodable {
      let name: String
      @ServerTimestamp var createdAt: Date?
    }

    let item = Item(name: "Test", createdAt: nil)
    let parser = FirestoreDocumentParser()
    let data = try parser.encode(item, documentName: "items/test")
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let fields = json["fields"] as! [String: Any]
    let createdAtField = fields["createdAt"]
    // When nil, @ServerTimestamp should encode as nullValue
    #expect(createdAtField != nil)
  }

  @Test func testIntArray() throws {
    let json = """
    {
      "fields": {
        "scores": {
          "arrayValue": {
            "values": [
              {"integerValue": "10"},
              {"integerValue": "20"},
              {"integerValue": "30"}
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct Scores: Decodable {
      let scores: [Int]
    }

    let parser = FirestoreDocumentParser()
    let result = try parser.decode(Scores.self, from: json)
    #expect(result.scores == [10, 20, 30])
  }

  // MARK: - FirestoreNormalizer + JSONDecoder tests

  @Test func testNormalizerSimpleDocument() throws {
    let json = """
    {
      "fields": {
        "name": {"stringValue": "Alice"},
        "age": {"integerValue": "30"},
        "active": {"booleanValue": "true"},
        "score": {"doubleValue": 95.5}
      }
    }
    """.data(using: .utf8)!

    struct User: Codable {
      let name: String
      let age: Int
      let active: Bool
      let score: Double
    }

    let user = try JSONDecoder().firestoreDecode(User.self, from: json)
    #expect(user.name == "Alice")
    #expect(user.age == 30)
    #expect(user.active == true)
    #expect(user.score == 95.5)
  }

  @Test func testNormalizerNestedDocument() throws {
    let json = """
    {
      "fields": {
        "name": {"stringValue": "Charlie"},
        "address": {
          "mapValue": {
            "fields": {
              "city": {"stringValue": "NYC"},
              "zip": {"integerValue": "10001"}
            }
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct Address: Codable {
      let city: String
      let zip: Int
    }
    struct User: Codable {
      let name: String
      let address: Address
    }

    let decoder = JSONDecoder()
    let user = try decoder.firestoreDecode(User.self, from: json)
    #expect(user.address.city == "NYC")
    #expect(user.address.zip == 10001)
  }

  @Test func testNormalizerWithDate() throws {
    let json = """
    {
      "fields": {
        "createdAt": {"timestampValue": "2024-06-15T10:30:00.000Z"}
      }
    }
    """.data(using: .utf8)!

    struct Event: Codable {
      let createdAt: String
    }

    let event = try JSONDecoder().firestoreDecode(Event.self, from: json)
    #expect(event.createdAt == "2024-06-15T10:30:00.000Z")
  }

  @Test func testNormalizerDocumentsList() throws {
    let json = """
    {
      "documents": [
        {
          "fields": {
            "name": {"stringValue": "Alice"}
          }
        },
        {
          "fields": {
            "name": {"stringValue": "Bob"}
          }
        }
      ]
    }
    """.data(using: .utf8)!

    struct User: Codable {
      let name: String
    }

    let users = try JSONDecoder().firestoreDecode([User].self, from: json)
    #expect(users.count == 2)
    #expect(users[0].name == "Alice")
    #expect(users[1].name == "Bob")
  }

  @Test func testNormalizerGeoPoint() throws {
    let json = """
    {
      "fields": {
        "location": {
          "geoPointValue": {
            "latitude": 37.7749,
            "longitude": -122.4194
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct Place: Codable {
      let location: GeoPoint
    }
    struct GeoPoint: Codable {
      let latitude: Double
      let longitude: Double
    }

    let place = try JSONDecoder().firestoreDecode(Place.self, from: json)
    #expect(place.location.latitude == 37.7749)
    #expect(place.location.longitude == -122.4194)
  }

  @Test func testNormalizerArray() throws {
    let json = """
    {
      "fields": {
        "tags": {
          "arrayValue": {
            "values": [
              {"stringValue": "swift"},
              {"stringValue": "firebase"}
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct Post: Codable {
      let tags: [String]
    }

    let post = try JSONDecoder().firestoreDecode(Post.self, from: json)
    #expect(post.tags == ["swift", "firebase"])
  }

  @Test func testNormalizerMixedArray() throws {
    let json = """
    {
      "fields": {
        "mixed": {
          "arrayValue": {
            "values": [
              {"stringValue": "hello"},
              {"integerValue": "42"},
              {"booleanValue": "true"},
              {"doubleValue": 3.14}
            ]
          }
        }
      }
    }
    """.data(using: .utf8)!

    let normalized = try FirestoreNormalizer.normalize(json)
    let flat = try JSONSerialization.jsonObject(with: normalized) as! [String: Any]
    let mixed = flat["mixed"] as! [Any]
    #expect(mixed[0] as? String == "hello")
    #expect(mixed[1] as? Int64 == 42)
    #expect(mixed[2] as? Bool == true)
    #expect(mixed[3] as? Double == 3.14)
  }

  // MARK: - Custom Decoder tests

  @Test func testDeeplyNestedMap() throws {
    let json = """
    {
      "fields": {
        "level1": {
          "mapValue": {
            "fields": {
              "level2": {
                "mapValue": {
                  "fields": {
                    "level3": {
                      "mapValue": {
                        "fields": {
                          "value": {"stringValue": "deep"}
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct L3: Decodable {
      let value: String
    }
    struct L2: Decodable {
      let level3: L3
    }
    struct L1: Decodable {
      let level2: L2
    }
    struct Root: Decodable {
      let level1: L1
    }

    let parser = FirestoreDocumentParser()
    let root = try parser.decode(Root.self, from: json)
    #expect(root.level1.level2.level3.value == "deep")
  }

  // MARK: - Document<T> Tests

  @Test func testDocumentSingle() throws {
    let json = """
    {
      "name": "projects/p/databases/d/documents/users/user42",
      "fields": {
        "name": {"stringValue": "Alice"},
        "age": {"integerValue": "30"}
      }
    }
    """.data(using: .utf8)!

    struct User: Decodable, Sendable {
      let name: String
      let age: Int64
    }

    let parser = FirestoreDocumentParser()
    let doc = try parser.decode(Document<User>.self, from: json)
    #expect(doc.documentID == "user42")
    #expect(doc.data.name == "Alice")
    #expect(doc.data.age == 30)
  }

  @Test func testDocumentList() throws {
    let json = """
    {
      "documents": [
        {
          "name": "projects/p/databases/d/documents/users/user1",
          "fields": {
            "name": {"stringValue": "Alice"}
          }
        },
        {
          "name": "projects/p/databases/d/documents/users/user2",
          "fields": {
            "name": {"stringValue": "Bob"}
          }
        }
      ]
    }
    """.data(using: .utf8)!

    struct User: Decodable, Sendable {
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let docs = try parser.decode([Document<User>].self, from: json)
    #expect(docs.count == 2)
    #expect(docs[0].documentID == "user1")
    #expect(docs[0].data.name == "Alice")
    #expect(docs[1].documentID == "user2")
    #expect(docs[1].data.name == "Bob")
  }

  @Test func testDocumentInArray() throws {
    let json = """
    [
      {
        "name": "projects/p/databases/d/documents/users/user1",
        "fields": {
          "name": {"stringValue": "Alice"}
        }
      },
      {
        "name": "projects/p/databases/d/documents/users/user2",
        "fields": {
          "name": {"stringValue": "Bob"}
        }
      }
    ]
    """.data(using: .utf8)!

    struct User: Decodable, Sendable {
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let docs = try parser.decode([Document<User>].self, from: json)
    #expect(docs.count == 2)
    #expect(docs[0].documentID == "user1")
    #expect(docs[1].documentID == "user2")
  }

  @Test func testDocumentWithDocumentIDWrapper() throws {
    let json = """
    {
      "name": "projects/p/databases/d/documents/users/user42",
      "fields": {
        "name": {"stringValue": "Alice"}
      }
    }
    """.data(using: .utf8)!

    struct User: Decodable, Sendable {
      @DocumentID var id: String?
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let doc = try parser.decode(Document<User>.self, from: json)
    #expect(doc.documentID == "user42")
    #expect(doc.data.id == "projects/p/databases/d/documents/users/user42")
    #expect(doc.data.name == "Alice")
  }

  @Test func testDecodeURL() throws {
    let json = """
    {
      "fields": {
        "url": {"stringValue": "https://example.com/path?q=1"},
        "name": {"stringValue": "Test"}
      }
    }
    """.data(using: .utf8)!

    struct Model: Decodable, Sendable {
      let url: URL
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let m = try parser.decode(Model.self, from: json)
    #expect(m.url.absoluteString == "https://example.com/path?q=1")
    #expect(m.name == "Test")
  }

  @Test func testDocumentWithNilName() throws {
    let json = """
    {
      "fields": {
        "name": {"stringValue": "NoDoc"}
      }
    }
    """.data(using: .utf8)!

    struct User: Decodable, Sendable {
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let doc = try parser.decode(Document<User>.self, from: json)
    #expect(doc.documentID == "")
    #expect(doc.data.name == "NoDoc")
  }

  @Test func testDateFromSecondsNanosecondsMap() throws {
    let json = """
    {
      "name": "projects/p/databases/(default)/documents/newCommunityRequests/id1",
      "fields": {
        "communityName": {"stringValue": "NS Talks"},
        "fieldDates": {
          "mapValue": {
            "fields": {
              "updatedAt": {
                "mapValue": {
                  "fields": {
                    "seconds": {"integerValue": "1779107400"},
                    "nanoseconds": {"integerValue": "0"}
                  }
                }
              },
              "createdAt": {
                "mapValue": {
                  "fields": {
                    "seconds": {"integerValue": "1779107400"},
                    "nanoseconds": {"integerValue": "0"}
                  }
                }
              }
            }
          }
        }
      }
    }
    """.data(using: .utf8)!

    struct FieldDates: Decodable {
      let createdAt: Date
      let updatedAt: Date
    }
    struct NewCommunityRequest: Decodable {
      let communityName: String
      let fieldDates: FieldDates
    }

    let parser = FirestoreDocumentParser()
    let req = try parser.decode(NewCommunityRequest.self, from: json)
    #expect(req.communityName == "NS Talks")
    let expected = Date(timeIntervalSince1970: 1779107400)
    #expect(req.fieldDates.createdAt == expected)
  }

  // MARK: - Pagination Tests

  @Test func testDecodePageWithNextToken() throws {
    let json = """
    {
      "nextPageToken": "token123",
      "documents": [
        {
          "name": "projects/p/databases/d/documents/users/user1",
          "fields": {
            "name": {"stringValue": "Alice"}
          }
        },
        {
          "name": "projects/p/databases/d/documents/users/user2",
          "fields": {
            "name": {"stringValue": "Bob"}
          }
        }
      ]
    }
    """.data(using: .utf8)!

    struct User: Decodable, Sendable {
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let page = try parser.decodePage(Document<User>.self, from: json)
    #expect(page.items.count == 2)
    #expect(page.nextPageToken == "token123")
    #expect(page.items[0].documentID == "user1")
    #expect(page.items[0].data.name == "Alice")
    #expect(page.items[1].documentID == "user2")
    #expect(page.items[1].data.name == "Bob")
  }

  @Test func testDecodePageLastPage() throws {
    let json = """
    {
      "documents": [
        {
          "name": "projects/p/databases/d/documents/users/user1",
          "fields": {
            "name": {"stringValue": "Alice"}
          }
        }
      ]
    }
    """.data(using: .utf8)!

    struct User: Decodable, Sendable {
      let name: String
    }

    let parser = FirestoreDocumentParser()
    let page = try parser.decodePage(Document<User>.self, from: json)
    #expect(page.items.count == 1)
    #expect(page.nextPageToken == nil)
  }
}
