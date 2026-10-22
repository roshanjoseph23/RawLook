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
      // The original v1.0.0 JSON ships in the test bundle; the app bundle has the tuned one.
      let bundle = Bundle(for: Self.self)
      let url = try XCTUnwrap(
        bundle.url(forResource: "warm-garden-portraits", withExtension: "json"))
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

  func testOpenablePhotoFileFiltering() throws {
    for suffix in ["RAF", "raf", "dng", "CR3", "nef", "arw"] {
      XCTAssertTrue(OpenablePhotoFile.isRAW(pathExtension: suffix), suffix)
      XCTAssertTrue(OpenablePhotoFile.isOpenable(pathExtension: suffix), suffix)
    }
    for suffix in ["jpg", "JPEG", "heic", "HEIF", "png", "tif", "TIFF"] {
      XCTAssertFalse(OpenablePhotoFile.isRAW(pathExtension: suffix), suffix)
      XCTAssertTrue(OpenablePhotoFile.isOpenable(pathExtension: suffix), suffix)
    }
    for suffix in ["", "gif", "bmp", "pdf", "mov", "txt", "json", "xmp"] {
      XCTAssertFalse(OpenablePhotoFile.isOpenable(pathExtension: suffix), suffix)
    }
    XCTAssertTrue(OpenablePhotoFile.isOpenable(URL(fileURLWithPath: "/tmp/DSCF0001.RAF")))
    XCTAssertFalse(OpenablePhotoFile.isOpenable(URL(fileURLWithPath: "/tmp/DSCF0001.RAF.xmp")))
    XCTAssertFalse(OpenablePhotoFile.isOpenable(try XCTUnwrap(URL(string: "https://example.com/a.jpg"))))

    let urls = ["notes.txt", "a.raf", "b.jpg", "c.gif"].map { URL(fileURLWithPath: "/tmp/" + $0) }
    let pick = OpenablePhotoFile.pick(urls, where: OpenablePhotoFile.isOpenable)
    XCTAssertEqual(pick?.item.lastPathComponent, "a.raf")
    XCTAssertEqual(pick?.ignoredCount, 3)
    XCTAssertNil(OpenablePhotoFile.pick([URL(fileURLWithPath: "/tmp/x.gif")], where: OpenablePhotoFile.isOpenable))
    XCTAssertNil(OpenablePhotoFile.pick([URL](), where: OpenablePhotoFile.isOpenable))
    XCTAssertEqual(OpenablePhotoFile.pick(Array(urls[1...1]), where: OpenablePhotoFile.isOpenable)?.ignoredCount, 0)
    XCTAssertNil(OpenablePhotoFile.ignoredNotice(0))
    XCTAssertEqual(OpenablePhotoFile.ignoredNotice(1), "Opened the first photo. 1 other item was ignored.")
    XCTAssertEqual(OpenablePhotoFile.ignoredNotice(3), "Opened the first photo. 3 other items were ignored.")
  }

  private func curveState() -> EditState {
    var state = EditState()
    state.curves = Array(repeating: [[0, 0], [0.5, 0.5], [1, 1]], count: 4)
    state.normalizeCurveIDs()
    return state
  }

  func testCurveRemovalByIDNeverLeavesStaleRows() {
    var state = curveState()
    let before = state.curveItems(0)
    XCTAssertEqual(before.map(\.position), [0, 1, 2])
    XCTAssertTrue(state.removeCurvePoint(channel: 0, id: before[1].id))
    let after = state.curveItems(0)
    XCTAssertEqual(after.map(\.id), [before[0].id, before[2].id])
    XCTAssertEqual(after.map(\.position), [0, 1])
    // A second removal with the now-stale id, or of an endpoint, is a no-op rather than a crash.
    XCTAssertFalse(state.removeCurvePoint(channel: 0, id: before[1].id))
    XCTAssertFalse(state.removeCurvePoint(channel: 0, id: before[0].id))
    XCTAssertFalse(state.removeCurvePoint(channel: 0, id: before[2].id))
    XCTAssertFalse(state.removeCurvePoint(channel: 9, id: before[0].id))
    XCTAssertNil(state.curvePosition(channel: 0, id: before[1].id))
    state.adjustCurvePointOutput(channel: 0, id: before[1].id, by: 0.1)
    state.moveCurvePoint(channel: 0, id: before[1].id, input: 0.3, output: 0.3)
    XCTAssertEqual(state.curves[0], [[0, 0], [1, 1]])
    XCTAssertEqual(state.curves[1].count, 3)
  }

  func testCurveInsertMoveAndClamp() throws {
    var state = curveState()
    let id = try XCTUnwrap(state.insertCurvePoint(channel: 2, input: 0.25, output: 1.4))
    XCTAssertEqual(state.curvePosition(channel: 2, id: id), 1)
    XCTAssertEqual(state.curves[2][1], [0.25, 1])
    XCTAssertNil(state.insertCurvePoint(channel: 2, input: 0.252, output: 0.5))
    XCTAssertNil(state.insertCurvePoint(channel: 2, input: 0, output: 0.5))
    XCTAssertNil(state.insertCurvePoint(channel: 7, input: 0.4, output: 0.5))
    state.moveCurvePoint(channel: 2, id: id, input: 0.9, output: -1)
    XCTAssertEqual(state.curves[2][1][0], 0.5 - EditState.minCurvePointGap, accuracy: 1e-6)
    XCTAssertEqual(state.curves[2][1][1], 0)
    let end = state.curveItems(2)[3].id
    state.moveCurvePoint(channel: 2, id: end, input: 0.2, output: 0.8)
    XCTAssertEqual(state.curves[2][3], [1, 0.8])
    XCTAssertEqual(state.curveIDs[2].count, state.curves[2].count)
  }

  func testCurveIDNormalizationRepairsMismatchedShapes() {
    var state = EditState()
    state.curves = [[[0, 0], [1, 1]], [[0, 0], [0.5, 0.4], [1, 1]]]
    state.curveIDs = [[UUID(), UUID(), UUID()]]
    XCTAssertEqual(state.curveItems(1).count, 0)
    state.normalizeCurveIDs()
    XCTAssertEqual(state.curveIDs.map(\.count), [2, 3])
    XCTAssertEqual(state.curveItems(1).count, 3)
    XCTAssertEqual(Set(state.curveIDs.flatMap { $0 }).count, 5)
  }

  func testNearestCurvePoint() {
    let state = curveState()
    let mid = state.curveItems(0)[1].id
    XCTAssertEqual(
      state.nearestCurvePoint(
        channel: 0, location: (105, 95), scale: (200, 200), radius: 24), mid)
    XCTAssertNil(
      state.nearestCurvePoint(channel: 0, location: (50, 20), scale: (200, 200), radius: 24))
    XCTAssertNil(
      state.nearestCurvePoint(channel: 5, location: (100, 100), scale: (200, 200), radius: 24))
  }
}
