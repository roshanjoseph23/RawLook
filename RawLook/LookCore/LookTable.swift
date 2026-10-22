import Foundation

/// Row zero holds HSL anchors; rows one through four hold master, red, green and blue knots.
/// Each row has sixteen RGBA float pixels, padded with zeros.
enum LookTable {
  static func pack(anchors: [Preset.Anchor], curves: [[[Float]]]) throws -> [Float] {
    guard (1...16).contains(anchors.count), curves.count == 4 else { throw PresetError.anchors }
    for curve in curves { try Preset.validateCurve(curve) }
    var pixels = [Float](repeating: 0, count: 16 * 5 * 4)
    for (index, anchor) in anchors.enumerated() {
      let offset = index * 4
      pixels.replaceSubrange(
        offset..<offset + 4,
        with: [
          anchor.hueDegrees, anchor.hueDeltaDegrees, anchor.saturationMultiplier,
          anchor.lightnessAdjustment
        ])
    }
    for (row, curve) in curves.enumerated() {
      for (index, point) in curve.enumerated() {
        let offset = ((row + 1) * 16 + index) * 4
        pixels[offset] = point[0]
        pixels[offset + 1] = point[1]
      }
    }
    return pixels
  }
}
