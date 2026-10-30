import MCP

/// Tool definitions exposed by the Firestore MCP server.
public enum FirestoreTools {
  public static let getDocument = "firestore_get_document"
  public static let listDocuments = "firestore_list_documents"
  public static let listCollections = "firestore_list_collections"

  public static let all: [Tool] = [
    Tool(
      name: getDocument,
      title: "Get Firestore document",
      description: """
      Fetch a Firestore document by its relative path, for example users/alice. \
      Returns the document ID, full name, timestamps, and decoded fields. \
      Read-only.
      """,
      inputSchema: [
        "type": "object",
        "properties": [
          "path": [
            "type": "string",
            "description": "Document path, for example users/alice.",
          ],
          "mask": [
            "type": "string",
            "description": "Optional comma-separated field paths to return, for example name,email.",
          ],
        ],
        "required": ["path"],
      ],
      annotations: .init(readOnlyHint: true, openWorldHint: false)
    ),
    Tool(
      name: listDocuments,
      title: "List Firestore documents",
      description: """
      List documents in a collection, for example users or users/alice/orders. \
      Returns one page of documents plus nextPageToken when more are available. \
      Read-only.
      """,
      inputSchema: [
        "type": "object",
        "properties": [
          "collection": [
            "type": "string",
            "description": "Collection path, for example users or users/alice/orders.",
          ],
          "pageSize": [
            "type": "integer",
            "description": "Number of documents per page (1...1000).",
            "minimum": 1,
            "maximum": 1000,
          ],
          "pageToken": [
            "type": "string",
            "description": "Token from a previous response's nextPageToken.",
          ],
        ],
        "required": ["collection"],
      ],
      annotations: .init(readOnlyHint: true, openWorldHint: false)
    ),
    Tool(
      name: listCollections,
      title: "List Firestore collections",
      description: """
      List collection paths at the database root, or the subcollections of a \
      document when parent is provided. Returns one page plus nextPageToken when \
      more are available. Read-only.
      """,
      inputSchema: [
        "type": "object",
        "properties": [
          "parent": [
            "type": "string",
            "description": "Optional document path whose subcollections should be listed, for example users/alice. Omit for top-level collections.",
          ],
          "pageSize": [
            "type": "integer",
            "description": "Number of collections per page (1...1000).",
            "minimum": 1,
            "maximum": 1000,
          ],
          "pageToken": [
            "type": "string",
            "description": "Token from a previous response's nextPageToken.",
          ],
        ],
      ],
      annotations: .init(readOnlyHint: true, openWorldHint: false)
    ),
  ]
}
