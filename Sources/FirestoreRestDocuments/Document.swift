import Foundation

public struct Document<T: Decodable> {
  public let documentID: String
  public let data: T
}

extension Document: Decodable {
  public init(from decoder: Decoder) throws {
    let name = decoder.userInfo[CodingUserInfoKey.documentNameUserInfoKey] as? String ?? ""
    self.documentID = (name as NSString).lastPathComponent
    self.data = try T(from: decoder)
  }
}

extension Document: Sendable where T: Sendable {}
