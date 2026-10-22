import Foundation
import XCTest

#if os(Linux)
  @testable import RawLookCore
#else
  @testable import RawLook
#endif

final class LookCoreTests: XCTestCase {
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
  func testBundledPreset() throws {
    let p = try preset()
    XCTAssertEqual(p.schemaVersion, "1.0.0")
    XCTAssertEqual(p.estimatedCreativePipeline.hslSectorAdjustments.anchors.count, 8)
    XCTAssertTrue(try p.validate().isEmpty)
    XCTAssertEqual(p.rawDevelopmentContract.rawStageControls.exposureEv.default, 0)
  }
  func testPresetEncodingAndLenientEffects() throws {
    let p = try preset()
    let encoded = try p.encoded()
    XCTAssertEqual(try Preset.decode(encoded), p)
    let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
    XCTAssertTrue(json.contains("schema_id"))
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    var pipeline = try XCTUnwrap(object["estimated_creative_pipeline"] as? [String: Any])
    pipeline["extra_effects"] = [
      "future_effect": ["enabled": true], "description_only": ["note": "ignored"]
    ]
    object["estimated_creative_pipeline"] = pipeline
    let result = try Preset.decode(JSONSerialization.data(withJSONObject: object))
    XCTAssertEqual(try result.validate(), ["Unsupported effect enabled: future_effect"])
  }
  func testValidation() throws {
    var p = try preset()
    p.schemaId = "other"
    XCTAssertThrowsError(try p.validate()) { XCTAssertEqual($0 as? PresetError, .schema) }
    p = try preset()
    p.schemaVersion = "2.0"
    XCTAssertThrowsError(try p.validate())
    p = try preset()
    p.estimatedCreativePipeline.masterRgbToneCurve.points = [[0, 0], [0.5, 0.5], [0.4, 1]]
    XCTAssertThrowsError(try p.validate())
    p = try preset()
    p.estimatedCreativePipeline.executionOrder.reverse()
    XCTAssertThrowsError(try p.validate())
    p = try preset()
    p.estimatedCreativePipeline.hslSectorAdjustments.anchors[1].hueDegrees = 0
    XCTAssertThrowsError(try p.validate())
    p = try preset()
    p.estimatedCreativePipeline.masterRgbToneCurve.points[0][1] = .infinity
    XCTAssertThrowsError(try p.validate())
  }
  func testCurve() {
    let p: [[Float]] = [[0.1, 0.2], [0.5, 0.7], [0.9, 0.8]]
    XCTAssertEqual(LookMath.curve(-1, p), 0.2)
    XCTAssertEqual(LookMath.curve(2, p), 0.8)
    for knot in p { XCTAssertEqual(LookMath.curve(knot[0], p), knot[1], accuracy: 1e-7) }
    XCTAssertEqual(LookMath.curve(0.3, p), 0.45, accuracy: 1e-6)
  }
  func testSectors() throws {
    let anchors = try preset().estimatedCreativePipeline.hslSectorAdjustments.anchors
    for a in anchors {
      let v = LookMath.sector(a.hueDegrees, anchors)
      XCTAssertEqual(v[0], a.hueDeltaDegrees, accuracy: 1e-6)
      XCTAssertEqual(v[1], a.saturationMultiplier, accuracy: 1e-6)
      XCTAssertEqual(v[2], a.lightnessAdjustment, accuracy: 1e-6)
    }
    XCTAssertEqual(LookMath.sector(90, anchors)[0], -5.5, accuracy: 1e-6)
    XCTAssertEqual(LookMath.sector(330, anchors)[1], 1, accuracy: 1e-6)
    XCTAssertEqual(LookMath.sector(-30, anchors), LookMath.sector(330, anchors))
  }
  func testNeutralProtection() {
    XCTAssertEqual(LookMath.weight(0.03), 0)
    XCTAssertEqual(LookMath.weight(0.105), 0.5, accuracy: 1e-6)
    XCTAssertEqual(LookMath.weight(0.18), 1, accuracy: 1e-6)
  }
  func testTransferFunctions() {
    XCTAssertEqual(LookMath.decode(0.04045), 0.003130805, accuracy: 1e-8)
    XCTAssertEqual(LookMath.decode(0.5), 0.21404114, accuracy: 1e-7)
    XCTAssertEqual(LookMath.encode(0.0031308), 0.040449936, accuracy: 1e-8)
    for i in 0...1000 {
      let x = Float(i) / 1000
      XCTAssertEqual(LookMath.encode(LookMath.decode(x)), x, accuracy: 1e-6)
    }
  }
  func testStrengthAndHSLRoundTrip() throws {
    let p = try preset().estimatedCreativePipeline
    var seed: UInt64 = 42
    // Determinism is intentional: these seeded LCG samples make test failures reproducible.
    func nextUnitSample() -> Float {
      seed = seed &* 6_364_136_223_846_793_005 &+ 1
      return Float(seed >> 40) / Float(0xFFFFFF)
    }
    var noBlend = p
    noBlend.executionOrder.removeAll { $0 == "strength_blend_linear_srgb" }
    for _ in 0..<2000 {
      let c = [nextUnitSample(), nextUnitSample(), nextUnitSample()]
      let identity = LookMath.apply(c, pipeline: p, strength: 0)
      let full = LookMath.apply(c, pipeline: p, strength: 1)
      let expected = LookMath.apply(c, pipeline: noBlend, strength: 1)
      let round = LookMath.rgb(LookMath.hsl(c))
      for i in 0..<3 {
        XCTAssertEqual(identity[i], c[i], accuracy: 1e-6)
        XCTAssertEqual(full[i], expected[i], accuracy: 1e-6)
        XCTAssertEqual(round[i], c[i], accuracy: 1e-6)
      }
    }
    XCTAssertEqual(LookMath.hsl([0.5, 0.5, 0.5]), [0, 0, 0.5])
  }
  func testEditStateRoundTrip() throws {
    var state = EditState()
    state.exposure = 1.5
    state.whiteBalanceMode = .manual
    state.temperature = 5200
    state.tint = -12
    state.crop = .init(x: 0.1, y: 0.2, width: 0.4, height: 0.6)
    state.curves = [[[0, 0], [1, 1]]]
    state.curveIDs = [[UUID(), UUID()]]
    state.adjustments[.brilliance] = 0.4
    XCTAssertEqual(
      try JSONDecoder().decode(EditState.self, from: JSONEncoder().encode(state)), state)
  }
  func testAspectResize() {
    let original = CropGeometry.Rect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
    let result = CropGeometry.constrainAspect(
      .init(x: 0.1, y: 0.1, width: 0.8, height: 0.9), original: original, ratio: 1.5, left: true,
      bottom: true, vertical: false)
    XCTAssertEqual(result.width / result.height, 1.5, accuracy: 1e-9)
    XCTAssertGreaterThanOrEqual(result.x, 0)
    XCTAssertGreaterThanOrEqual(result.y, 0)
    XCTAssertLessThanOrEqual(result.x + result.width, 1)
    XCTAssertLessThanOrEqual(result.y + result.height, 1)
  }
  func testCropGeometry() {
    let zero = CropGeometry.inscribed(width: 6000, height: 4000, radians: 0)
    XCTAssertEqual(zero.width, 6000)
    XCTAssertEqual(zero.height, 4000)
    for degrees in -45...45 {
      let angle = Double(degrees) * Double.pi / 180
      let size = CropGeometry.inscribed(width: 6000, height: 4000, radians: angle)
      XCTAssertLessThanOrEqual(
        size.width * abs(cos(angle)) + size.height * abs(sin(angle)), 6000.00001)
      XCTAssertLessThanOrEqual(
        size.width * abs(sin(angle)) + size.height * abs(cos(angle)), 4000.00001)
      XCTAssertEqual(size.width / size.height, 1.5, accuracy: 1e-9)
    }
    let fit = CropGeometry.fit(aspect: 1, imageAspect: 1.5)
    XCTAssertEqual(fit.width, 2 / 3, accuracy: 1e-9)
    XCTAssertEqual(fit.height, 1)
    let clamped = CropGeometry.clamp(.init(x: -1, y: 2, width: 2, height: 0))
    XCTAssertEqual(clamped.x, 0)
    XCTAssertEqual(clamped.y, 0.99)
  }
  func testTablePackingLayout() throws {
    let anchors = [
      Preset.Anchor(
        name: "Test", hueDegrees: 42, hueDeltaDegrees: -3, saturationMultiplier: 0.8,
        lightnessAdjustment: 0.1)
    ]
    let curves: [[[Float]]] = (0..<4).map { channel in [[0, Float(channel) / 10], [1, 1]] }
    let table = try LookTable.pack(anchors: anchors, curves: curves)
    XCTAssertEqual(table.count, 320)
    XCTAssertEqual(Array(table[0..<4]), [42, -3, 0.8, 0.1])
    XCTAssertTrue(table[4..<64].allSatisfy { $0 == 0 })
    for row in 1...4 {
      let offset = row * 64
      XCTAssertEqual(Array(table[offset..<offset + 8]), [0, Float(row - 1) / 10, 0, 0, 1, 1, 0, 0])
      XCTAssertTrue(table[offset + 8..<offset + 64].allSatisfy { $0 == 0 })
    }
    XCTAssertThrowsError(try LookTable.pack(anchors: anchors, curves: []))
    XCTAssertThrowsError(
      try LookTable.pack(anchors: anchors, curves: Array(repeating: [[0, 0]], count: 4)))
  }
  func testTypedModesAndCropSnapshot() throws {
    var state = EditState()
    state.cropAspect = .fourFive
    state.cropPortrait = true
    state.whiteBalanceMode = .manual
    state.adjustments[.sharpness] = 0.5
    XCTAssertEqual(
      try JSONDecoder().decode(EditState.self, from: JSONEncoder().encode(state)), state)
    XCTAssertNil(CropAspect.free.ratio(imageAspect: 1.5, portrait: false))
    XCTAssertEqual(CropAspect.original.ratio(imageAspect: 1.5, portrait: true), 1.5)
    XCTAssertEqual(CropAspect.fourFive.ratio(imageAspect: 1.5, portrait: true), 0.8)
    XCTAssertEqual(CropAspect.fourFive.ratio(imageAspect: 1.5, portrait: false), 1.25)
    for adjustment in Adjustment.allCases {
      XCTAssertTrue(adjustment.range.contains(adjustment.neutralValue))
    }
    XCTAssertEqual(ExportFormat.allCases.map(\.fileExtension), ["jpg", "tiff", "heic"])
    XCTAssertEqual(CurveChannel.allCases.map(\.rawValue), [0, 1, 2, 3])
  }

}
