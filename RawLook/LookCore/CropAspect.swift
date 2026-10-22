enum CropAspect: String, Codable, Sendable, CaseIterable {
  case free, original, square, fourFive, threeTwo, sixteenNine
  var displayName: String {
    switch self {
    case .free: "Free"
    case .original: "Original"
    case .square: "1:1"
    case .fourFive: "4:5"
    case .threeTwo: "3:2"
    case .sixteenNine: "16:9"
    }
  }
  /// Pixel aspect is converted to normalized crop coordinates by dividing by the image aspect.
  func ratio(imageAspect: Double, portrait: Bool) -> Double? {
    let value: Double
    switch self {
    case .free: return nil
    case .original: return imageAspect
    case .square: value = 1
    case .fourFive: value = 4.0 / 5
    case .threeTwo: value = 1.5
    case .sixteenNine: value = 16.0 / 9
    }
    return portrait ? min(value, 1 / value) : max(value, 1 / value)
  }
}
