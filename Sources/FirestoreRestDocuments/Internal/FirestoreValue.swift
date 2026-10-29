import Foundation

public indirect enum FirestoreValue: Sendable {
  case null
  case bool(Bool)
  case int(Int64)
  case double(Double)
  case string(String)
  case bytes(Data)
  case timestamp(Date)
  case geoPoint(latitude: Double, longitude: Double)
  case reference(String)
  case array([FirestoreValue])
  case map([String: FirestoreValue])
  case document(name: String, fields: [String: FirestoreValue])
}

extension FirestoreValue: Equatable {
  public static func == (lhs: FirestoreValue, rhs: FirestoreValue) -> Bool {
    switch (lhs, rhs) {
    case (.null, .null): return true
    case let (.bool(a), .bool(b)): return a == b
    case let (.int(a), .int(b)): return a == b
    case let (.double(a), .double(b)): return a == b
    case let (.string(a), .string(b)): return a == b
    case let (.bytes(a), .bytes(b)): return a == b
    case let (.timestamp(a), .timestamp(b)): return a == b
    case let (.geoPoint(la, lo), .geoPoint(ra, ro)): return la == ra && lo == ro
    case let (.reference(a), .reference(b)): return a == b
    case let (.array(a), .array(b)): return a == b
    case let (.map(a), .map(b)): return a == b
    case let (.document(an, af), .document(bn, bf)): return an == bn && af == bf
    default: return false
    }
  }
}
