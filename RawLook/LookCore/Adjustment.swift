enum Adjustment: String, Codable, Sendable, CaseIterable {
  case brightness, contrast, brilliance, highlights, shadows, saturation, vibrance, clarity,
    sharpness, vignette
  var displayName: String { rawValue.capitalized }
  var range: ClosedRange<Float> { self == .sharpness || self == .vignette ? 0...1 : -1...1 }
  var neutralValue: Float { 0 }
}
