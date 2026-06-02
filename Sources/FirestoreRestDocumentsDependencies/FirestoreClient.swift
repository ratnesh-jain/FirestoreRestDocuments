import Foundation
import FirestoreRestDocuments

public protocol FirestoreClient: Sendable {
  func decode<T: Decodable>(_ type: T.Type, from path: String) async throws -> T
  func fetch(from path: String) async throws -> Data
  func encode<T: Encodable>(_ value: T, documentName: String?) throws -> Data
  func fetchPage<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int?, pageToken: String?
  ) async throws -> FirestorePage<T>
}

extension FirestoreClient {
  public func fetchAll<T: Decodable>(
    _ type: T.Type, from path: String,
    pageSize: Int? = nil
  ) async throws -> [T] {
    var allItems = [T]()
    var pageToken: String? = nil
    repeat {
      let page = try await fetchPage(type, from: path, pageSize: pageSize, pageToken: pageToken)
      allItems.append(contentsOf: page.items)
      pageToken = page.nextPageToken
    } while pageToken != nil
    return allItems
  }
}
