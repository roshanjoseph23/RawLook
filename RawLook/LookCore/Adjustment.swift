enum Adjustment: String, Codable, Sendable, CaseIterable {
  case brightness, contrast, brilliance, highlights, shadows, saturation, vibrance, clarity,
    sharpness, vignette
  var displayName: String { rawValue.capitalized }
  /// Vignette is -1...1: negative values brighten the corners (to offset lens vignetting when the
  /// RAW decoder has no lens correction for the lens), positive values darken them.
  var range: ClosedRange<Float> { self == .sharpness ? 0...1 : -1...1 }
  var neutralValue: Float { 0 }
}
