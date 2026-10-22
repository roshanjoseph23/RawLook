import Foundation

/// A preset-owned white-balance offset applied on top of each photo's own white balance
/// (as shot or the per-photo Temperature/Tint sliders), before the creative look.
///
/// JSON (inside `estimated_creative_pipeline`, optional, every field defaults to 0):
/// `"white_balance_shift": { "temperature_shift_mireds": 12, "tint_shift": 3 }`
/// - `temperature_shift_mireds`: positive warms. Applied in mireds so the same shift feels
///   similar at any base temperature: `K' = 1e6 / (1e6 / K - shift)`.
/// - `tint_shift`: positive adds magenta, negative adds green (Camera RAW tint units).
/// Both scale with the look's strength.
struct WhiteBalanceShift: Codable, Sendable, Equatable {
  var temperatureShiftMireds: Float = 0
  var tintShift: Float = 0

  static let zero = WhiteBalanceShift()
  static let mireLimit: Float = 150
  static let tintLimit: Float = 150

  init(temperatureShiftMireds: Float = 0, tintShift: Float = 0) {
    self.temperatureShiftMireds = temperatureShiftMireds
    self.tintShift = tintShift
  }
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    temperatureShiftMireds =
      try container.decodeIfPresent(Float.self, forKey: .temperatureShiftMireds) ?? 0
    tintShift = try container.decodeIfPresent(Float.self, forKey: .tintShift) ?? 0
  }

  var isZero: Bool { temperatureShiftMireds == 0 && tintShift == 0 }
  var isWithinLimits: Bool {
    temperatureShiftMireds.isFinite && tintShift.isFinite
      && abs(temperatureShiftMireds) <= Self.mireLimit && abs(tintShift) <= Self.tintLimit
  }

  /// The shift blended by the look strength (0 = none, 1 = full).
  func scaled(by strength: Float) -> WhiteBalanceShift {
    let s = min(1, max(0, strength))
    return WhiteBalanceShift(temperatureShiftMireds: temperatureShiftMireds * s, tintShift: tintShift * s)
  }

  /// RAW path: the white-balance temperature to develop with, given the photo's own value.
  func kelvin(from base: Float) -> Float {
    let base = min(Self.maxKelvin, max(Self.minKelvin, base))
    let mireds = max(1e6 / Self.maxKelvin, 1e6 / base - temperatureShiftMireds)
    return min(Self.maxKelvin, max(Self.minKelvin, 1e6 / mireds))
  }
  /// RAW path: the tint to develop with, given the photo's own value.
  func tint(from base: Float) -> Float { base + tintShift }

  static let minKelvin: Float = 1700
  static let maxKelvin: Float = 25000

  /// Rendered-image path (JPEG/HEIC/...) and CPU reference: per-channel gains in linear sRGB.
  /// Von Kries scaling between Planckian whites at `base` and the shifted temperature, with
  /// tint as a green gain; normalised so Rec. 709 luminance of a grey is unchanged.
  func linearGains(baseKelvin: Float = 6500) -> [Float] {
    if isZero { return [1, 1, 1] }
    let from = Self.planckianLinearSRGB(min(Self.maxKelvin, max(Self.minKelvin, baseKelvin)))
    let to = Self.planckianLinearSRGB(kelvin(from: baseKelvin))
    var gains = zip(from, to).map { $0 / $1 }
    gains[1] *= exp(-0.0025 * tintShift)
    let luminance = 0.2126 * gains[0] + 0.7152 * gains[1] + 0.0722 * gains[2]
    return gains.map { $0 / luminance }
  }

  /// Linear sRGB of the Planckian white at `kelvin` (Kim et al. cubic fit, Y = 1).
  static func planckianLinearSRGB(_ kelvin: Float) -> [Float] {
    let t = Double(kelvin)
    let x: Double =
      t <= 4000
      ? -0.2661239e9 / (t * t * t) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910
      : -3.0258469e9 / (t * t * t) + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390
    let y: Double
    if t <= 2222 {
      y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
    } else if t <= 4000 {
      y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
    } else {
      y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
    }
    let X = x / y
    let Z = (1 - x - y) / y
    return [
      3.2406 * X - 1.5372 - 0.4986 * Z,
      -0.9689 * X + 1.8758 + 0.0415 * Z,
      0.0557 * X - 0.2040 + 1.0570 * Z
    ].map { Float(max($0, 0.001)) }
  }
}
