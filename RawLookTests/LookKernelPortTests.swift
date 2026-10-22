import Foundation
import XCTest

#if os(Linux)
  @testable import RawLookCore
#else
  @testable import RawLook
#endif

/// A line-by-line Swift port of `RawLook/Processing/Look.metal` that reads its data only from the
/// packed `LookTable` floats, exactly as the GPU kernel samples the uploaded 80x1 table image.
/// It guards the GPU data path (packing, row offsets, counts, flags) against the CPU reference.
private enum KernelPort {
  static func wrapHue(_ hue: Float) -> Float {
    let value = fmodf(hue, 360)
    return value < 0 ? value + 360 : value
  }
  static func dec(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4) }
  static func enc(_ v: Float) -> Float { v <= 0.0031308 ? 12.92 * v : 1.055 * powf(v, 1 / 2.4) - 0.055 }
  static func clamp01(_ v: Float) -> Float { min(max(v, 0), 1) }

  static func toHSL(_ c: SIMD3<Float>) -> SIMD3<Float> {
    let high = max(c.x, max(c.y, c.z))
    let low = min(c.x, min(c.y, c.z))
    let delta = high - low
    let lightness = (high + low) / 2
    if delta == 0 { return SIMD3(0, 0, lightness) }
    let hue =
      high == c.x ? (c.y - c.z) / delta : high == c.y ? (c.z - c.x) / delta + 2 : (c.x - c.y) / delta + 4
    return SIMD3(wrapHue(hue * 60), delta / (1 - abs(2 * lightness - 1)), lightness)
  }
  static func toRGB(_ hsl: SIMD3<Float>) -> SIMD3<Float> {
    let hue = wrapHue(hsl.x) / 60
    let chroma = (1 - abs(2 * hsl.z - 1)) * hsl.y
    let x = chroma * (1 - abs(fmodf(hue, 2) - 1))
    let offset = hsl.z - chroma / 2
    let value: SIMD3<Float> =
      hue < 1 ? SIMD3(chroma, x, 0) : hue < 2 ? SIMD3(x, chroma, 0) : hue < 3 ? SIMD3(0, chroma, x)
      : hue < 4 ? SIMD3(0, x, chroma) : hue < 5 ? SIMD3(x, 0, chroma) : SIMD3(chroma, 0, x)
    return value + offset
  }
  static func curve(_ x: Float, _ points: [SIMD4<Float>], _ count: Int) -> Float {
    var a = points[0]
    if x <= a.x { return a.y }
    for i in 1..<max(count, 1) {
      let b = points[i]
      if x <= b.x { return a.y + ((x - a.x) / (b.x - a.x)) * (b.y - a.y) }
      a = b
    }
    return a.y
  }
  static func sectorColor(_ color: SIMD3<Float>, _ anchors: [SIMD4<Float>], _ count: Int) -> SIMD3<Float> {
    var hsl = toHSL(color)
    var a = anchors[count - 1]
    var b = anchors[0]
    var hue = hsl.x
    var left = a.x
    var right = b.x + 360
    if hue < b.x { hue += 360 }
    for i in 1..<max(count, 1) where hue >= anchors[i - 1].x && hue < anchors[i].x {
      a = anchors[i - 1]
      b = anchors[i]
      left = a.x
      right = b.x
      break
    }
    let ayzw = SIMD3(a.y, a.z, a.w)
    let byzw = SIMD3(b.y, b.z, b.w)
    let parameters = ayzw + ((hue - left) / (right - left)) * (byzw - ayzw)
    let t = clamp01((hsl.y - 0.03) / 0.15)
    let weight = t * t * (3 - 2 * t)
    let delta = weight * parameters.z
    hsl.x = wrapHue(hsl.x + weight * parameters.x)
    hsl.y = clamp01(hsl.y * (1 + weight * (parameters.y - 1)))
    hsl.z = clamp01(hsl.z + delta * (delta >= 0 ? 1 - hsl.z : hsl.z))
    return toRGB(hsl)
  }

  /// Mirrors LookFilter's argument construction and the kernel body. Input/output: encoded sRGB.
  static func apply(_ srgb: [Float], preset: Preset, strength: Float) throws -> [Float] {
    let p = preset.estimatedCreativePipeline
    let curves = [
      p.masterRgbToneCurve.points, p.perChannelToneCurves.red, p.perChannelToneCurves.green,
      p.perChannelToneCurves.blue
    ]
    let table = try LookTable.pack(anchors: p.hslSectorAdjustments.anchors, curves: curves)
    let rows = (0..<LookTable.rowCount).map { row in
      (0..<LookTable.entriesPerRow).map { LookTable.entry(table, row: row, entry: $0) }
    }
    let has: (String, Bool) -> Bool = { p.executionOrder.contains($0) && $1 }
    let counts = curves.map(\.count)
    // Core Image hands the kernel linear premultiplied pixels (alpha 1 here).
    let linear = SIMD3(dec(srgb[0]), dec(srgb[1]), dec(srgb[2]))
    let original = SIMD3(clamp01(enc(linear.x)), clamp01(enc(linear.y)), clamp01(enc(linear.z)))
    var color = original
    if has("hsl_sector_adjustments", p.hslSectorAdjustments.enabled) {
      color = sectorColor(color, rows[0], p.hslSectorAdjustments.anchors.count)
    }
    if has("master_rgb_tone_curve", p.masterRgbToneCurve.enabled) {
      color = SIMD3(
        curve(color.x, rows[1], counts[0]), curve(color.y, rows[1], counts[0]),
        curve(color.z, rows[1], counts[0]))
    }
    if has("per_channel_tone_curves", p.perChannelToneCurves.enabled) {
      color = SIMD3(
        curve(color.x, rows[2], counts[1]), curve(color.y, rows[3], counts[2]),
        curve(color.z, rows[4], counts[3]))
    }
    if has("global_hsl_saturation", p.globalHslSaturation.enabled) {
      var hsl = toHSL(color)
      hsl.y = clamp01(hsl.y * p.globalHslSaturation.multiplier)
      color = toRGB(hsl)
    }
    if p.executionOrder.contains("strength_blend_linear_srgb") {
      let s = clamp01(strength)
      color = SIMD3(
        enc(dec(original.x) * (1 - s) + dec(color.x) * s),
        enc(dec(original.y) * (1 - s) + dec(color.y) * s),
        enc(dec(original.z) * (1 - s) + dec(color.z) * s))
    }
    color = SIMD3(clamp01(color.x), clamp01(color.y), clamp01(color.z))
    // Kernel returns linear; re-encode to compare in the same space as LookMath.
    return [color.x, color.y, color.z].map { enc(dec($0)) }
  }
}

final class LookKernelPortTests: XCTestCase {
  private func preset() throws -> Preset {
    #if os(Linux)
      let url = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
          "Presets/source/warm-garden-portraits.json")
    #else
      let bundle = Bundle.main
      let url = try XCTUnwrap(
        bundle.url(
          forResource: "warm-garden-portraits", withExtension: "json",
          subdirectory: "Presets/source")
          ?? bundle.url(forResource: "warm-garden-portraits", withExtension: "json"))
    #endif
    return try Preset.decode(Data(contentsOf: url))
  }

  private let chart: [[Float]] = [
    [115, 82, 68], [194, 150, 130], [98, 122, 157], [87, 108, 67], [133, 128, 177],
    [103, 189, 170], [214, 126, 44], [80, 91, 166], [193, 90, 99], [94, 60, 108],
    [157, 188, 64], [224, 163, 46], [56, 61, 150], [70, 148, 73], [175, 54, 60],
    [231, 199, 31], [187, 86, 149], [8, 133, 161]
  ].map { $0.map { $0 / 255 } }

  private var greys: [[Float]] { (0...20).map { Float($0) / 20 }.map { [$0, $0, $0] } }

  func testPackedTableRoundTripsThroughKernelLayout() throws {
    let p = try preset().estimatedCreativePipeline
    let curves = [
      p.masterRgbToneCurve.points, p.perChannelToneCurves.red, p.perChannelToneCurves.green,
      p.perChannelToneCurves.blue
    ]
    let table = try LookTable.pack(anchors: p.hslSectorAdjustments.anchors, curves: curves)
    // Uploaded as one row of `width` RGBA float pixels.
    XCTAssertEqual(LookTable.width, 80)
    XCTAssertEqual(table.count, LookTable.width * 4)
    for (i, a) in p.hslSectorAdjustments.anchors.enumerated() {
      XCTAssertEqual(
        LookTable.entry(table, row: 0, entry: i),
        SIMD4(a.hueDegrees, a.hueDeltaDegrees, a.saturationMultiplier, a.lightnessAdjustment))
    }
    for (row, curve) in curves.enumerated() {
      for (i, point) in curve.enumerated() {
        XCTAssertEqual(LookTable.entry(table, row: row + 1, entry: i), SIMD4(point[0], point[1], 0, 0))
      }
      for i in curve.count..<LookTable.entriesPerRow {
        XCTAssertEqual(LookTable.entry(table, row: row + 1, entry: i), .zero)
      }
    }
    // The blue curve must be the last 16 entries, which the kernel reads at x = 64...79.
    XCTAssertEqual(LookTable.pixelIndex(row: 4, entry: 0), 64)
  }

  func testKernelPortMatchesCPUReferenceAndIsMild() throws {
    let preset = try preset()
    var samples = greys + chart
    var rng = SystemRandomNumberGenerator()
    for _ in 0..<500 { samples.append((0..<3).map { _ in Float.random(in: 0...1, using: &rng) }) }
    var maxGPUvsCPU: Float = 0
    for (index, rgb) in samples.enumerated() {
      let gpu = try KernelPort.apply(rgb, preset: preset, strength: 1)
      let cpu = LookMath.apply(rgb, pipeline: preset.estimatedCreativePipeline, strength: 1)
      let diff = zip(gpu, cpu).map { abs($0 - $1) }.max() ?? 0
      maxGPUvsCPU = max(maxGPUvsCPU, diff)
      let change = zip(gpu, rgb).map { abs($0 - $1) }.max() ?? 0
      if index < greys.count {
        XCTAssertLessThan(change, 0.04, "grey \(rgb) -> \(gpu)")
        // Greys stay grey: no channel may collapse (the old bug zeroed blue).
        XCTAssertLessThan((gpu.max() ?? 0) - (gpu.min() ?? 0), 0.02, "grey \(rgb) -> \(gpu)")
      } else if index < greys.count + chart.count {
        XCTAssertLessThan(change, 0.10, "chart \(rgb) -> \(gpu)")
      }
    }
    XCTAssertLessThan(maxGPUvsCPU, 1 / 255)
  }

  func testStrengthZeroIsIdentity() throws {
    let preset = try preset()
    for rgb in greys + chart {
      let gpu = try KernelPort.apply(rgb, preset: preset, strength: 0)
      for (a, b) in zip(gpu, rgb) { XCTAssertEqual(a, b, accuracy: 1e-4) }
    }
  }
}
