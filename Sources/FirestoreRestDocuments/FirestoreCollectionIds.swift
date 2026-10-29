import Foundation

/// One page of collection IDs returned by `documents:listCollectionIds`.
public struct FirestoreCollectionIdsPage: Codable, Sendable {
  public let collectionIds: [String]
  public let nextPageToken: String?

  public init(collectionIds: [String], nextPageToken: String? = nil) {
    self.collectionIds = collectionIds
    self.nextPageToken = nextPageToken
  }

  enum CodingKeys: String, CodingKey {
    case collectionIds
    case nextPageToken
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.collectionIds = try container.decodeIfPresent([String].self, forKey: .collectionIds) ?? []
    self.nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
  }
}
