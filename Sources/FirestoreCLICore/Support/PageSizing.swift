enum PageSizing {
  static let defaultFollowAllSize = 1000

  /// Page size to request, or nil to keep the server default.
  static func size(
    requested: Int?,
    limit: Int?,
    alreadyFetched: Int,
    followAll: Bool
  ) -> Int? {
    if let requested { return requested }
    guard followAll || limit != nil else { return nil }
    guard let limit else { return defaultFollowAllSize }
    return min(defaultFollowAllSize, max(1, limit - alreadyFetched))
  }
}
