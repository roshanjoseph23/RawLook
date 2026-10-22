import Foundation

/// Numeric data for the GPU look kernel.
///
/// Logical row zero holds HSL anchors; rows one through four hold master, red, green and blue
/// knots. Each logical row has sixteen RGBA float entries, padded with zeros.
///
/// The rows are uploaded back to back as a single-row image (`width` x 1). A multi-row image
/// must not be used: Core Image places bitmap row zero at the top of a bottom-left-origin
/// coordinate space, which flips the rows the kernel reads (anchors and the blue curve swap).
enum LookTable {
  static let entriesPerRow = 16
  static let rowCount = 5
  /// Pixel width of the uploaded one-pixel-high table image.
  static let width = entriesPerRow * rowCount

  /// Horizontal pixel index of an entry; the kernel samples at `index + 0.5, 0.5`.
  static func pixelIndex(row: Int, entry: Int) -> Int { row * entriesPerRow + entry }

  /// The RGBA float entry the kernel reads for `row` and `entry`.
  static func entry(_ pixels: [Float], row: Int, entry: Int) -> SIMD4<Float> {
    let offset = pixelIndex(row: row, entry: entry) * 4
    return SIMD4(pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
  }

  static func pack(anchors: [Preset.Anchor], curves: [[[Float]]]) throws -> [Float] {
    guard (1...16).contains(anchors.count), curves.count == 4 else { throw PresetError.anchors }
    for curve in curves { try Preset.validateCurve(curve) }
    var pixels = [Float](repeating: 0, count: width * 4)
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
        let offset = pixelIndex(row: row + 1, entry: index) * 4
        pixels[offset] = point[0]
        pixels[offset + 1] = point[1]
      }
    }
    return pixels
  }
}
