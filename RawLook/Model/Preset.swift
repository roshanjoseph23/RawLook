import Foundation

struct Preset: Codable, Sendable, Equatable, Identifiable {
  var schemaId: String
  var schemaVersion: String
  var profileId: String
  var name: String
  var createdDate: String
  var intendedUse: String
  var rawDevelopmentContract: RawContract
  var estimatedCreativePipeline: Pipeline
  var id: String { profileId }

  struct RawContract: Codable, Sendable, Equatable {
    var rawStageControls: Controls
    struct Controls: Codable, Sendable, Equatable {
      var exposureEv: Exposure
      var whiteBalance: WhiteBalance
      struct Exposure: Codable, Sendable, Equatable { var `default`: Float }
      struct WhiteBalance: Codable, Sendable, Equatable { var defaultMode: String }
    }
  }
  struct Pipeline: Codable, Sendable, Equatable {
    var defaultStrength: Float
    var executionOrder: [String]
    var hslSectorAdjustments: Sectors
    var masterRgbToneCurve: Curve
    var perChannelToneCurves: Channels
    var globalHslSaturation: Saturation
    var strengthBlendLinearSrgb: Strength
    var extraEffects: [String: Effect]
    struct Sectors: Codable, Sendable, Equatable {
      var enabled: Bool
      var anchors: [Anchor]
    }
    struct Curve: Codable, Sendable, Equatable {
      var enabled: Bool
      var points: [[Float]]
    }
    struct Channels: Codable, Sendable, Equatable {
      var enabled: Bool
      var red: [[Float]]
      var green: [[Float]]
      var blue: [[Float]]
    }
    struct Saturation: Codable, Sendable, Equatable {
      var enabled: Bool
      var multiplier: Float
    }
    struct Strength: Codable, Sendable, Equatable { var defaultStrength: Float }
    struct Effect: Codable, Sendable, Equatable {
      var enabled: Bool
      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decode(Bool.self, forKey: .enabled)) ?? false
      }
      enum CodingKeys: String, CodingKey { case enabled }
    }
  }
  struct Anchor: Codable, Sendable, Equatable {
    var name: String
    var hueDegrees: Float
    var hueDeltaDegrees: Float
    var saturationMultiplier: Float
    var lightnessAdjustment: Float
  }
  static func decode(_ data: Data) throws -> Preset {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let preset = try decoder.decode(Preset.self, from: data)
    _ = try preset.validate()
    return preset
  }
  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    return try encoder.encode(self)
  }
  static let supportedOrder = [
    "hsl_sector_adjustments", "master_rgb_tone_curve", "per_channel_tone_curves",
    "global_hsl_saturation", "strength_blend_linear_srgb", "output_srgb"
  ]
  func validate() throws -> [String] {
    guard schemaId == "reference-photo-look" else { throw PresetError.schema }
    guard schemaVersion.split(separator: ".").first == "1" else { throw PresetError.version }
    let p = estimatedCreativePipeline
    var previous = -1
    for stage in p.executionOrder {
      guard let index = Self.supportedOrder.firstIndex(of: stage), index > previous else {
        throw PresetError.order
      }
      previous = index
    }
    let anchors = p.hslSectorAdjustments.anchors
    guard (1...16).contains(anchors.count) else { throw PresetError.anchors }
    var last: Float = -1
    for a in anchors {
      guard
        [a.hueDegrees, a.hueDeltaDegrees, a.saturationMultiplier, a.lightnessAdjustment].allSatisfy(
          \.isFinite), a.hueDegrees >= 0, a.hueDegrees < 360, a.hueDegrees > last
      else { throw PresetError.anchors }
      last = a.hueDegrees
    }
    for curve in [
      p.masterRgbToneCurve.points, p.perChannelToneCurves.red, p.perChannelToneCurves.green,
      p.perChannelToneCurves.blue
    ] { try Self.validateCurve(curve) }
    guard
      [
        p.defaultStrength, p.strengthBlendLinearSrgb.defaultStrength,
        p.globalHslSaturation.multiplier,
        rawDevelopmentContract.rawStageControls.exposureEv.default
      ].allSatisfy(\.isFinite), (0...1).contains(p.defaultStrength),
      (0...1).contains(p.strengthBlendLinearSrgb.defaultStrength)
    else { throw PresetError.nonfinite }
    return p.extraEffects.filter { $0.value.enabled }.keys.sorted().map {
      "Unsupported effect enabled: \($0)"
    }
  }
  static func validateCurve(_ points: [[Float]]) throws {
    guard (2...16).contains(points.count) else { throw PresetError.curve }
    var last: Float = -1
    for point in points {
      guard point.count == 2, point.allSatisfy(\.isFinite), (0...1).contains(point[0]),
        point[0] > last
      else { throw PresetError.curve }
      last = point[0]
    }
  }
}
