import Foundation

final class FirestoreValueBox {
  let value: FirestoreValue

  init(_ value: FirestoreValue) {
    self.value = value
  }
}

final class FirestoreKeyedValueBox {
  let value: [String: FirestoreValue]

  init(_ value: [String: FirestoreValue]) {
    self.value = value
  }
}
