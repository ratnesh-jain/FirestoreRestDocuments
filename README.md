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
- **Write operations** — `commit`, `batchWrite`, `batchGet`, and a `FirestoreBatch` builder for create/update/delete via the REST API
- **Command-line tool** — `frd` for reading, writing, deleting, batching, and listing collections from a terminal or shell script
- **Dependencies** — `swift-log` and `swift-crypto` for the base library; optional `swift-dependencies` integration via separate product
- **Service account auth** — mint and auto-refresh OAuth2 tokens from a service account JSON key

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
| `frd` | — | Command-line executable for reading and writing documents |

| `frd-mcp` | — | Read-only MCP server executable (stdio transport) exposing Firestore tools to MCP clients |

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

### Write operations

Create, update, and delete documents through the REST API using `commit` or `batchWrite`:

```swift
let db = FirestoreDocument(config: config)

// Create
let write = try FirestoreWrite.create(newUser, at: "users/new-user")
let response = try await db.commit(writes: [write])

// Update (with field mask)
let update = try FirestoreWrite.update(user, at: "users/abc123", updateMask: ["email"])
_ = try await db.commit(writes: [update])

// Delete
_ = try await db.commit(writes: [.delete(at: "users/abc123")])

// Batch multiple writes atomically
var batch = FirestoreBatch()
try batch.create(newUser, at: "users/new")
try batch.update(user, at: "users/existing", updateMask: ["email"])
batch.delete(at: "users/old")
let result = try await batch.commit(using: db)
```

`create` sends `currentDocument.exists = false`, so it fails if the document already exists. Use `update` (with no update mask) for an upsert.

`batchWrite` is the non-transactional variant (per-write status reporting):

```swift
let response = try await db.batchWrite(writes: writes, labels: ["env": "prod"])
```

### Batch get

Fetch multiple documents in one request:

```swift
let results = try await db.batchGet(documents: ["users/u1", "users/u2"])
for result in results {
  if case .found(let doc) = result {
    print(doc.name, doc.fields)
  }
}

// Typed convenience
let users = try await db.batchGet(User.self, documents: ["users/u1", "users/u2"])
```
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
- `baseURL` — defaults to `https://firestore.googleapis.com/v1`; set it to target the Firestore emulator or a proxy.

### Service account authentication (automatic token refresh)

For long-running servers, you can hand the library a service account JSON key and let it mint and refresh OAuth2 tokens automatically:

```swift
// From a decoded service account
let account = try JSONDecoder().decode(
  FirestoreServiceAccount.self,
  from: Data(contentsOf: URL(fileURLWithPath: "serviceAccount.json"))
)
let config = FirestoreConfig(
  projectId: "my-project",
  serviceAccount: account
)

// Or directly from a file path
let config = try FirestoreConfig(
  projectId: "my-project",
  serviceAccountKeyFileAtPath: "serviceAccount.json"
)

let db = FirestoreDocument(config: config)
// Tokens are minted on first request and refreshed ~60s before expiry.
```

You can also implement `FirestoreAccessTokenProvider` for custom credential sources (gcloud, ADC, Vault, etc.).

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
  func batchGet(documents: [String], mask: FirestoreDocumentMask?) async throws -> [FirestoreBatchGetResult]
  func commit(writes: [FirestoreWrite], transaction: String?) async throws -> FirestoreCommitResponse
  func batchWrite(writes: [FirestoreWrite], labels: [String: String]?) async throws -> FirestoreBatchWriteResponse
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

## Command-Line Tool

The package includes an `frd` (short for FirestoreRestDocuments) executable so the same REST operations can be used from a terminal or shell script.

```bash
swift run frd --help

# Build a standalone binary
swift build -c release
.build/release/frd --help
```

### Commands

| Command | Description |
|---|---|
| `get <document>` | Fetch one document and print its fields as JSON. |
| `list <collection>` | List documents (one page by default; `--all` follows `nextPageToken`). |
| `collections` | List collection paths at the database root, or under `--parent <document>`. |
| `set <path>` | Create or replace a document. Supports `--merge`, `--mask`, `--create-only`, `--if-exists`. |
| `update <document>` | Merge the provided top-level fields. Supports `--mask`, `--replace`, `--if-exists`. |
| `delete <document...>` | Delete one or more documents atomically. |
| `batch-get <document...>` | Fetch multiple documents in one request. |
| `batch-write` | Apply a JSON batch of create/set/update/delete operations. |

Shared options (`--project`, `--token`, `--service-account`, output flags, and so on) are accepted by every subcommand; place them after the subcommand name:

```bash
frd get users/alice --project my-project --token "$(gcloud auth print-access-token)"
```

### Authentication

Credentials are resolved in this order:

1. `--token <token>` or `FIRESTORE_ACCESS_TOKEN` / `GOOGLE_OAUTH_ACCESS_TOKEN`
2. `--token-file <path>`
3. `--service-account <key.json>` or `GOOGLE_APPLICATION_CREDENTIALS`
4. `--api-key <key>` or `FIRESTORE_API_KEY` / `GOOGLE_API_KEY`

The project ID comes from `--project`, `FIRESTORE_PROJECT_ID`, `GOOGLE_CLOUD_PROJECT`, `GCLOUD_PROJECT`, or the service account's `project_id`. The database defaults to `(default)`; override it with `--database` or `FIRESTORE_DATABASE_ID`.

These environment variables are read by every command; explicit flags always take precedence:

| Variable | Used for | Notes |
|---|---|---|
| `FIRESTORE_PROJECT_ID` | Project ID | Highest-priority environment fallback. |
| `GOOGLE_CLOUD_PROJECT` | Project ID | Used when `FIRESTORE_PROJECT_ID` is unset. |
| `GCLOUD_PROJECT` | Project ID | Last project fallback before the service account's `project_id`. |
| `FIRESTORE_DATABASE_ID` | Database ID | Defaults to `(default)`. |
| `FIRESTORE_ACCESS_TOKEN` | Access token | Sent as `Authorization: Bearer <token>`. |
| `GOOGLE_OAUTH_ACCESS_TOKEN` | Access token | Fallback for `FIRESTORE_ACCESS_TOKEN`. |
| `GOOGLE_APPLICATION_CREDENTIALS` | Service account key path | Used when no access token is set. |
| `FIRESTORE_API_KEY` | API key | Sent as `?key=`, only when no token is available. |
| `GOOGLE_API_KEY` | API key | Fallback for `FIRESTORE_API_KEY`. |
| `FIRESTORE_EMULATOR_HOST` | Emulator host | For example `localhost:8080`; overrides the base URL. |
| `FIRESTORE_LOG_LEVEL` | Log level | For example `debug`, `info`, or `error`. |

`--token-file` has no environment variable; pass the path with the flag.

```bash
# Service account (tokens are minted and refreshed automatically)
frd list users --project my-project --service-account ~/keys/service-account.json

# Environment variables
export FIRESTORE_PROJECT_ID=my-project
export FIRESTORE_ACCESS_TOKEN="$(gcloud auth print-access-token)"
frd get users/alice

# Firestore emulator
frd get users/alice --project demo --emulator-host localhost:8080
# or: export FIRESTORE_EMULATOR_HOST=localhost:8080
```

`--verbose` prints library debug logs to stderr. JSON output always goes to stdout, so commands compose with `jq` and other tools.

### Reading

```bash
frd get users/alice
frd get users/alice --raw > alice.json        # unmodified REST response
frd list users --limit 10 --compact
frd list users --all
frd list users/alice/orders --page-size 25 --page-token "$TOKEN"
frd batch-get users/alice users/bob --mask name,email
frd collections                                # top-level collections
frd collections --parent users/alice --all     # subcollections of a document
```

`get` prints only the document's fields. `list` prints an array of `{ id, name, createTime, updateTime, data }` objects. `batch-get` prints an array in request order, with `"found": true/false` and a `data` object for documents that exist. `collections` prints a JSON array of collection paths, such as `["users","orders"]` or `["users/alice/orders"]` when `--parent` is used; pass `--all` or `--limit` to follow pagination, and `--raw` for the unmodified `listCollectionIds` response.

### Writing

Data is read from `--data`, `--file`, or stdin. Numbers, booleans, strings, nulls, arrays, and nested objects map to the matching Firestore types. Use `set` to replace a document, or `--merge` to write only the provided top-level fields:

```bash
frd set users/alice --project p --data '{"name":"Alice","age":30}'
frd set users/alice --project p --merge --data '{"age":31}'
frd set users --project p --merge --data '{"name":"Alice"}'   # generated document ID
frd update users/alice --project p --mask name,email --data '{"name":"Alice","email":"a@example.com"}'
echo '{"active":true}' | frd update users/alice --project p
frd delete users/alice users/bob --project p
```

- `set` replaces the document; fields that are not in the payload are removed. `--merge` or `--mask` makes it a partial update.
- `set` with a collection path (for example `users`) generates a document ID and prints the resulting path. Use `--id` to choose the ID.
- `--create-only` fails when the document already exists; `--if-exists` fails when it does not.
- `--dry-run` prints the exact `documents:commit` (or `:batchWrite`) request body without sending it, so it works without credentials as long as a project ID is known.

#### Typed values

Flat JSON cannot express Firestore timestamps, references, geo points, or bytes. Use these single-key objects; `get --raw` output (and `{"fields": {...}}` documents) can also be written back directly, preserving all types:

```json
{
  "createdAt": {"$timestamp": "2024-06-15T10:30:00Z"},
  "owner": {"$reference": "users/alice"},
  "location": {"$geopoint": {"latitude": 37.77, "longitude": -122.42}},
  "avatar": {"$bytes": "SGVsbG8="},
  "count": {"$integer": "42"},
  "ratio": {"$double": 1.5},
  "metadata": {"$literal": {"$timestamp": "this is a normal field name"}}
}
```

`$reference` accepts either a full `projects/.../documents/...` path or a short `collection/document` path relative to the configured project and database.

### Batch writes

```bash
frd batch-write --project p --file operations.json
cat operations.json | frd batch-write --project p --non-atomic --label env=prod
```

```json
[
  {"op": "create", "path": "users/u1", "data": {"name": "Alice"}},
  {"op": "update", "path": "users/u1", "data": {"name": "Bob"}, "mask": ["name"]},
  {"op": "set", "path": "users/u2", "data": {"name": "Carol"}},
  {"op": "delete", "path": "users/u3"}
]
```

- Operations are committed atomically by default. `--non-atomic` uses `batchWrite`, which returns a per-write status and accepts `--label key=value`.
- For `update`, the default mask is the provided top-level fields; set `"replace": true` or provide `"mask"` to change that. For `set`, `"mask"` is optional.
- `"exists": true/false` adds a precondition to `set`/`update` operations.
- An object with a `"writes"` array is also accepted instead of a bare array.

## MCP Server

The package also ships a read-only [Model Context Protocol](https://modelcontextprotocol.io/) server, `frd-mcp`, that exposes Firestore operations as MCP tools over stdio. It is intended for use with MCP clients (Claude Desktop, Claude Code, Cursor, etc.).

```bash
# Build a standalone binary
swift build -c release --product frd-mcp

# Run directly (requires environment variables; see Authentication)
FIRESTORE_PROJECT_ID=my-project FIRESTORE_ACCESS_TOKEN="$(gcloud auth print-access-token)" \\
  .build/release/frd-mcp
```

### Tools

| Tool | Description |
|---|---|
| `firestore_get_document` | Fetch one document by path (optional comma-separated `mask`). |
| `firestore_list_documents` | List documents in a collection, with `pageSize` and `pageToken`. |
| `firestore_list_collections` | List top-level collections, or subcollections when `parent` is given. |

All tools are read-only. Credentials are never accepted as tool arguments; they come from the same environment variables as `frd`.

### Tool arguments

`firestore_get_document`

| Argument | Type | Required | Description |
|---|---|---|---|
| `path` | string | yes | Document path, for example `users/alice`. |
| `mask` | string | no | Comma-separated field paths, for example `name,email`. |

`firestore_list_documents`

| Argument | Type | Required | Description |
|---|---|---|---|
| `collection` | string | yes | Collection path, for example `users` or `users/alice/orders`. |
| `pageSize` | integer | no | Page size (1–1000). |
| `pageToken` | string | no | Token from a previous response. |

`firestore_list_collections`

| Argument | Type | Required | Description |
|---|---|---|---|
| `parent` | string | no | Document path whose subcollections to list; omit for top-level collections. |
| `pageSize` | integer | no | Page size (1–1000). |
| `pageToken` | string | no | Token from a previous response. |

### Example prompts

Once configured, you can ask your MCP client things like:

- "List the top-level Firestore collections."
- "Show the first 10 documents in the `users` collection."
- "Get the document `users/alice`, but only the `name` and `email` fields."
- "What subcollections does `users/alice` have?"

Tool results are JSON objects. `firestore_list_documents` and `firestore_list_collections` include `nextPageToken` when more pages are available; pass it back as `pageToken` to continue.

### Client configuration

Example for Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "firestore": {
      "command": "/path/to/frd-mcp",
      "env": {
        "FIRESTORE_PROJECT_ID": "my-project",
        "FIRESTORE_ACCESS_TOKEN": "ya29...."
      }
    }
  }
}
```

Example for Claude Code (`.mcp.json` in your project):

```json
{
  "mcpServers": {
    "firestore": {
      "command": "/path/to/frd-mcp",
      "env": {
        "FIRESTORE_PROJECT_ID": "my-project",
        "GOOGLE_APPLICATION_CREDENTIALS": "/path/to/service-account.json"
      }
    }
  }
}
```

Or build from source with `swift build -c release --product frd-mcp` and point `command` at `.build/release/frd-mcp`.

### Authentication

`frd-mcp` resolves credentials from the environment using the same rules as `frd` (see the environment variable table above). `FIRESTORE_PROJECT_ID` (or `GOOGLE_CLOUD_PROJECT` / `GCLOUD_PROJECT`) and one credential source are required at startup; the server fails fast with an error on stderr if they are missing.

Logs are written to stderr so stdout remains the MCP JSON-RPC channel. Set `FIRESTORE_LOG_LEVEL=debug` (or `info`) to increase verbosity when troubleshooting.

### Troubleshooting

- **Server exits immediately / client shows no tools** — check stderr. Missing project ID or credentials produce a single `frd-mcp: ...` error line.
- **`401 UNAUTHENTICATED`** — the access token is expired or invalid; mint a new one with `gcloud auth print-access-token`.
- **Emulator** — set `FIRESTORE_EMULATOR_HOST=localhost:8080` (and a project ID such as `demo`); the server targets the emulator's REST endpoint.
- **No write tools** — by design this server is read-only; writes are only available through the `frd` CLI.

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
├── FirestoreBatch           # FirestoreBatch builder for writes
├── FirestoreBatchOperation # FirestoreWrite, masks, and batch responses
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

FirestoreCLICore/ (depends on base + swift-argument-parser)
├── FirestoreCommand         # root command and subcommand list
├── GlobalOptions            # auth/config/output flags and environment fallback
├── Commands/                # get, list, collections, set, update, delete, batch-get, batch-write
└── Support/                 # JSON conversion, path validation, output

FirestoreCLI/ (executable)
└── EntryPoint               # bootstraps swift-log and runs FirestoreCommand
```

The package has **five layers**:

1. **Normalizer** — recursively unwraps `{"stringValue": "Alice"}` → `"Alice"`, then passes flat JSON to `JSONDecoder`. Best when you don't need property wrappers.

2. **Custom Decoder/Encoder** — implements Swift's `Decoder`/`Encoder` protocols directly on the `FirestoreValue` tree. Handles `Date`, `Data`, `GeoPoint`, and property wrappers natively.

3. **Unified API** — `FirestoreDocument` combines URL construction, authentication, async networking, and decoding into one call.

4. **Dependencies** — protocol-based `FirestoreClient` with live/mock implementations, registered as `@Dependency` values for clean DI and testability.

5. **Command-line tool** — `frd` wraps the unified API with subcommands, environment-based credential discovery, JSON output, and batch-file support.

## Limitations

- The package does **not** include a full Firestore client (transactions, realtime listeners, or complex queries). It's designed for straightforward document reads, writes, and list operations via the REST API.
- Authentication requires obtaining a Firebase Auth ID token or OAuth2 access token separately.
- The `@DocumentID` property wrapper populates from the document's `name` field (full path), not just the short document ID.

## License

Apache 2.0
