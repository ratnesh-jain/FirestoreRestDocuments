import Foundation

public struct FirestorePage<T: Decodable> {
  public let items: [T]
  public let nextPageToken: String?
}

extension FirestorePage: Sendable where T: Sendable {}
