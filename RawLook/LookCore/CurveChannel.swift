enum CurveChannel: Int, Codable, Sendable, CaseIterable {
  case master, red, green, blue
  var displayName: String { String(describing: self).capitalized }
}
