import Foundation

public struct FirestoreDocumentResponse: Codable {
  public let name: String?
  public let fields: [String: FirestoreFieldValue]?
  public let createTime: String?
  public let updateTime: String?
}

public struct FirestoreFieldValue: Codable {
  public var nullValue: String?
  public var booleanValue: String?
  public var integerValue: String?
  public var doubleValue: Double?
  public var stringValue: String?
  public var timestampValue: String?
  public var referenceValue: String?
  public var bytesValue: String?
  public var geoPointValue: GeoPointValue?
  public var arrayValue: FirestoreArrayValue?
  public var mapValue: FirestoreMapValue?

  public init() {}

  enum CodingKeys: String, CodingKey {
    case nullValue
    case booleanValue
    case integerValue
    case doubleValue
    case stringValue
    case timestampValue
    case referenceValue
    case bytesValue
    case geoPointValue
    case arrayValue
    case mapValue
  }
}

public struct GeoPointValue: Codable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}

public struct FirestoreArrayValue: Codable {
  public let values: [FirestoreFieldValue]?

  public init(values: [FirestoreFieldValue]?) {
    self.values = values
  }
}

public struct FirestoreMapValue: Codable {
  public let fields: [String: FirestoreFieldValue]?

  public init(fields: [String: FirestoreFieldValue]?) {
    self.fields = fields
  }
}

public struct FirestoreReadResult: Codable {
  public let document: FirestoreDocumentResponse?
  public let readTime: String?
}

public struct FirestoreListResult: Codable {
  public let documents: [FirestoreDocumentResponse]?
  public let nextPageToken: String?
}

public struct FirestoreRunQueryResult: Codable {
  public let document: FirestoreDocumentResponse?
  public let readTime: String?
  public let skippedResults: Int?
}

public struct FirestoreWriteResult: Codable {
  public let document: FirestoreDocumentResponse?
  public let writeResults: [FirestoreWriteResultEntry]?
  public let commitTime: String?
}

public struct FirestoreWriteResultEntry: Codable {
  public let updateTime: String?
  public let transformResults: [FirestoreFieldValue]?
}
