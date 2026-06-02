import Foundation

public struct FirestoreGeoPoint: Codable, Equatable, Hashable, Sendable {
  public var latitude: Double
  public var longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }

  enum CodingKeys: String, CodingKey {
    case latitude
    case longitude
  }
}
