# FirestoreRestDocuments

Parse Firestore documents directly from the [Firestore REST API](https://firebase.google.com/docs/firestore/reference/rest) responses into native Swift `Decodable` types — no Firebase SDK required.

## Features

- **Four API styles** — choose what fits your project:
  - `FirestoreDocument` — unified async API: configure once, then `decode(User.self, from: "users/user1")`
  - `FirestoreDocumentParser` — local parsing only (no networking): `parser.decode(User.self, from: jsonData)`
  - `JSONDecoder.firestoreDecode` — normalizer + standard `JSONDecoder`: `decoder.firestoreDecode(User.self, from: data)`
  - `@Dependency(\.firestoreClient)` — [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) integration for DI and testing
- **All Firestore value types** — string, integer, double, boolean, map, array, timestamp, geo point, reference, bytes, null
- **Property wrappers** — `@DocumentID`, `@ServerTimestamp`, `@ExplicitNull` (same API as the Firebase iOS SDK)
- **Encoding** — encode Swift models back to Firestore REST wire format
- **Zero dependencies** for the base library; optional `swift-dependencies` integration via separate product

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
  .package(url: "https://github.com/your-username/FirestoreRestDocuments.git", from: "0.1.0")
]
```

Or add via Xcode: **File → Add Package Dependencies...** → paste the URL.

### Products

| Product | Import | Description |
|---|---|---|
| `FirestoreRestDocuments` | `import FirestoreRestDocuments` | Base library (depends on `swift-log`) |
| `FirestoreRestDocumentsDependencies` | `import FirestoreRestDocumentsDependencies` | Adds [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) integration |

Add the product you need to your target:

```swift
.target(
  name: "MyTarget",
  dependencies: [
    .product(name: "FirestoreRestDocuments", package: "FirestoreRestDocuments")
    // or for Dependencies support:
    // .product(name: "FirestoreRestDocumentsDependencies", package: "FirestoreRestDocuments")
  ]
)
```

## Quick Start

### 1. Decode a single document

```swift
import FirestoreRestDocuments

let json = """
{
  "fields": {
    "name": {"stringValue": "Alice"},
    "age": {"integerValue": "30"},
    "active": {"booleanValue": "true"}
  }
}
""".data(using: .utf8)!

struct User: Decodable {
  let name: String
  let age: Int
  let active: Bool
}

let parser = FirestoreDocumentParser()
let user = try parser.decode(User.self, from: json)
print(user.name) // "Alice"
```

### 2. Fetch and decode from Firestore REST API

```swift
let config = FirestoreConfig(
  projectId: "my-project",
  accessToken: "ya29..." // Firebase Auth ID token or OAuth2 token
)

let db = FirestoreDocument(config: config)

// Single document
let user = try await db.decode(User.self, from: "users/user1")

// Collection (list documents)
let users = try await db.decode([User].self, from: "users")
```

### 3. Use JSONDecoder directly

```swift
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
decoder.dataDecodingStrategy = .base64

let user = try decoder.firestoreDecode(User.self, from: responseData)
```

## API Reference

### FirestoreDocument (unified async API)

Fetches data from Firestore REST API and decodes it in one call.

```swift
// Static (uses FirestoreConfig.shared)
FirestoreConfig.shared = config
let user = try await FirestoreDocument.decode(User.self, from: "users/user1")
let users = try await FirestoreDocument.decode([User].self, from: "users")

// Instance
let db = FirestoreDocument(config: config)
let user = try await db.decode(User.self, from: "users/user1")
let users = try await db.decode([User].self, from: "users")

// With custom JSONDecoder
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let user = try await db.decode(User.self, from: "users/user1", using: decoder)
```

**Path conventions:**

| Path | HTTP endpoint | Expected type |
|---|---|---|
| `"users"` | `ListDocuments` | `[T].self` |
| `"users/user1"` | `GetDocument` | `T.self` |
| `"users/user1/orders"` | `ListDocuments` (subcollection) | `[T].self` |

### FirestoreConfig

```swift
let config = FirestoreConfig(
  projectId: "my-project",       // Required
  databaseId: "(default)",       // Optional, defaults to "(default)"
  accessToken: "ya29...",        // Bearer token (preferred)
  apiKey: "AIza..."             // API key (fallback)
)
```

- `accessToken` — sent as `Authorization: Bearer <token>`. Use a Firebase Auth ID token or Google OAuth2 token.
- `apiKey` — appended as `?key=<apiKey>` query parameter. Simpler but less secure.
- `accessToken` takes priority when both are set.

### FirestoreDocumentParser (local parsing)

Parses JSON data you've already fetched (no networking). Supports all Firestore REST response shapes.

```swift
let parser = FirestoreDocumentParser()

// Single document (with "fields" key)
let user = try parser.decode(User.self, from: documentJSON)

// Array of documents (with "documents" key or raw array)
let users = try parser.decode([User].self, from: listJSON)

// RunQuery response (with "documentResults" key)
let results = try parser.decode([Result].self, from: queryJSON)

// Encode model to Firestore REST wire format
let data = try parser.encode(user, documentName: "users/new-user")
let fields = try parser.encodeAsFieldsDictionary(user)
```

### FirestoreNormalizer + JSONDecoder

Converts Firestore typed-value JSON to flat JSON, then decodes with standard `JSONDecoder`.

```swift
// Two-step
let flatData = try FirestoreNormalizer.normalize(responseData)
let user = try JSONDecoder().decode(User.self, from: flatData)

// One-step (extension)
let user = try JSONDecoder().firestoreDecode(User.self, from: responseData)
```

### Property Wrappers

#### @DocumentID

Populates a field with the document name from the Firestore response.

```swift
struct User: Decodable {
  @DocumentID var id: String?
  let name: String
  let email: String
}

// The "name" field from the document response becomes the @DocumentID value
// e.g. "projects/p/databases/d/documents/users/user42"
```

#### @ServerTimestamp

Decodes a `Timestamp` value as a `Date`. When encoding, `nil` values are included as `nullValue` (they would become `FieldValue.serverTimestamp()` on the server).

```swift
struct Item: Codable {
  let name: String
  @ServerTimestamp var createdAt: Date?
}
```

#### @ExplicitNull

Ensures `nil` fields are encoded as explicit Firestore null values instead of being omitted.

```swift
struct Profile: Codable {
  let name: String
  @ExplicitNull var nickname: String?
}
```

## Firestore REST JSON Format

This package understands the Firestore REST API wire format:

```json
{
  "fields": {
    "name":     {"stringValue": "Alice"},
    "age":      {"integerValue": "30"},
    "active":   {"booleanValue": "true"},
    "score":    {"doubleValue": 95.5},
    "tags":     {"arrayValue": {"values": [{"stringValue": "a"}, {"stringValue": "b"}]}},
    "address":  {"mapValue": {"fields": {"city": {"stringValue": "NYC"}, "zip": {"integerValue": "10001"}}}},
    "created":  {"timestampValue": "2024-06-15T10:30:00.000Z"},
    "location": {"geoPointValue": {"latitude": 37.77, "longitude": -122.42}},
    "ref":      {"referenceValue": "projects/p/databases/d/documents/c/doc"},
    "blob":     {"bytesValue": "SGVsbG8="},
    "missing":  {"nullValue": null}
  }
}
```

## Encoding

Encode Swift models back to the Firestore REST wire format.

```swift
struct Person: Codable {
  let name: String
  let age: Int
  let active: Bool
}

let person = Person(name: "Bob", age: 25, active: true)

// Full document (with "fields" wrapper)
let data = try parser.encode(person, documentName: "people/bob")

// Fields only (for merging into an existing document)
let fields = try parser.encodeAsFieldsDictionary(person)

// Fields as JSON Data
let fieldsData = try parser.encodeFields(person)
```

## Examples

### Full CRUD with Firestore REST API

```swift
let config = FirestoreConfig(projectId: "my-project", accessToken: token)
let db = FirestoreDocument(config: config)
let parser = FirestoreDocumentParser()

// CREATE
var newUser = User(name: "Alice", email: "alice@example.com")
let body = try parser.encode(newUser)
var request = try config.makeRequest(path: "users")
request.httpMethod = "POST"
request.httpBody = body
let (data, _) = try await URLSession.shared.data(for: request)
newUser = try parser.decode(User.self, from: data)

// READ
let user = try await db.decode(User.self, from: "users/abc123")

// UPDATE
user.email = "alice@newdomain.com"
let updateBody = try parser.encodeFields(user)
var updateReq = try config.makeRequest(path: "users/abc123")
updateReq.httpMethod = "PATCH"
updateReq.httpBody = updateBody
_ = try await URLSession.shared.data(for: updateReq)

// DELETE
var deleteReq = try config.makeRequest(path: "users/abc123")
deleteReq.httpMethod = "DELETE"
_ = try await URLSession.shared.data(for: deleteReq)
```

### Swift Dependencies Integration

The `FirestoreRestDocumentsDependencies` product adds [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) integration. Import it instead of `FirestoreRestDocuments`:

```swift
import FirestoreRestDocumentsDependencies  // also re-exports FirestoreRestDocuments
```

It registers two dependencies:

| Dependency | Type | Description |
|---|---|---|
| `\.defaultFirestoreConfig` | `FirestoreConfig` | The Firestore configuration used by live client |
| `\.firestoreClient` | `any FirestoreClient` | Protocol-based client (live or mock) |

#### App setup (entry point)

```swift
import Dependencies
import FirestoreRestDocumentsDependencies

prepareDependencies {
  $0.defaultFirestoreConfig = FirestoreConfig(
    projectId: "my-project",
    accessToken: token
  )
}

// Later, in your application code:
let users = try await FirestoreDocument.live.decode([User].self, from: "users")
```

#### Using `@Dependency`

```swift
import Dependencies
import FirestoreRestDocumentsDependencies

struct UsersService {
  @Dependency(\.firestoreClient) var client

  func loadUsers() async throws -> [User] {
    try await client.decode([User].self, from: "users")
  }
}
```

#### Testing with `MockFirestoreClient`

```swift
import Dependencies
import DependenciesTestSupport
import FirestoreRestDocumentsDependencies

let mock = MockFirestoreClient()
mock.decodeHandler = { type, path in
  [User(name: "Alice"), User(name: "Bob")]
}

let service = withDependencies {
  $0.firestoreClient = mock
} operation: {
  UsersService()
}

let users = try await service.loadUsers()
XCTAssertEqual(users.count, 2)
```

#### `FirestoreClient` protocol

```swift
public protocol FirestoreClient: Sendable {
  func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T
  func fetch(from path: String) async throws -> Data
  func encode<T: Encodable>(_ value: T, documentName: String?) throws -> Data
}
```

- **`LiveFirestoreClient`** — wraps `FirestoreDocument`, uses `defaultFirestoreConfig` from the dependency system
- **`MockFirestoreClient`** — stubbable handler closures for tests; throws by default if not set

#### Convenience: `FirestoreDocument.live`

```swift
// Reads config from @Dependency(\.defaultFirestoreConfig)
let db = FirestoreDocument.live
let users = try await db.decode([User].self, from: "users")
```

## Logging

The package uses [swift-log](https://github.com/apple/swift-log) for all internal logging with the label `com.firestorerestdocuments`.

By default, no logs are emitted — you must bootstrap a logging backend in your application's entry point.

### Server-side (with SwiftLog)

```swift
import Logging

LoggingSystem.bootstrap { label in
  var handler = StreamLogHandler.standardOutput(label: label)
  handler.logLevel = .info   // suppress trace/debug; show warning/error
  return handler
}
```

This applies to **all** loggers. To target only this package's logs (label `com.firestorerestdocuments`):

```swift
LoggingSystem.bootstrap { label in
  var handler = StreamLogHandler.standardOutput(label: label)
  handler.logLevel = label == "com.firestorerestdocuments" ? .debug : .info
  return handler
}
```

Set `logLevel` to one of: `.trace`, `.debug`, `.info`, `.notice`, `.warning`, `.error`, `.critical`. The default is `.info`.

### With swift-log backends

```swift
import Logging

// Use any swift-log backend (e.g. https://github.com/apple/swift-log, or a cloud provider)
LoggingSystem.bootstrap { label in
  MyCloudLogHandler(label: label)
}
```

Once bootstrapped, logs from the package will appear at the following levels:

| Level | Where |
|---|---|
| `trace` | `FirestoreNormalizer`, `FirestoreDocumentParser` (decode/encode) |
| `debug` | `FirestoreConfig` (request URL), `FirestoreDocument` (fetch path, response status) |
| `warning` | `FirestoreDocument` (HTTP errors) |
| `error` | `FirestoreConfig` (missing projectId), `FirestoreDocumentParser` (decode/encode failures) |

## Architecture
├── FirestoreDocument        # Unified async API (config + network + decode)
├── FirestoreConfig          # Project, database, auth configuration
├── FirestoreDocumentParser  # Local parsing/encoding (no networking)
├── FirestoreNormalizer      # Firestore JSON → flat JSON converter
├── PropertyWrappers         # @DocumentID, @ServerTimestamp, @ExplicitNull
├── FirestoreResponse        # REST API response Codable models
└── Internal/
    ├── FirestoreValue       # Internal value representation
    ├── FirestoreDecoderImpl # Custom Swift Decoder implementation
    └── FirestoreEncoderImpl # Custom Swift Encoder implementation

FirestoreRestDocumentsDependencies/ (depends on base + swift-dependencies)
├── FirestoreClient          # Async protocol for DI and testing
├── LiveFirestoreClient      # Production implementation
├── MockFirestoreClient      # Stubbable handler closures for tests
├── FirestoreClient+Dependency  # @Dependency(\.firestoreClient) registration
├── FirestoreConfig+Dependency # @Dependency(\.defaultFirestoreConfig) registration
└── FirestoreDocument+Dependency # FirestoreDocument.live convenience
```

The package has **four layers**:

1. **Normalizer** — recursively unwraps `{"stringValue": "Alice"}` → `"Alice"`, then passes flat JSON to `JSONDecoder`. Best when you don't need property wrappers.

2. **Custom Decoder/Encoder** — implements Swift's `Decoder`/`Encoder` protocols directly on the `FirestoreValue` tree. Handles `Date`, `Data`, `GeoPoint`, and property wrappers natively.

3. **Unified API** — `FirestoreDocument` combines URL construction, authentication, async networking, and decoding into one call.

4. **Dependencies** — protocol-based `FirestoreClient` with live/mock implementations, registered as `@Dependency` values for clean DI and testability.

## Limitations

- The package does **not** include a full Firestore client (transactions, realtime listeners, or complex queries). It's designed for straightforward document reads, writes, and list operations via the REST API.
- Authentication requires obtaining a Firebase Auth ID token or OAuth2 access token separately.
- The `@DocumentID` property wrapper populates from the document's `name` field (full path), not just the short document ID.

## License

Apache 2.0
