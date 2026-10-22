import Foundation
import XCTest

#if os(Linux)
  @testable import RawLookCore
#else
  @testable import RawLook
#endif

/// Port of `shoulder` in Look.metal, kept line-by-line so the GPU and CPU stay in sync.
private func metalShoulder(_ x: Float, _ start: Float) -> Float {
  if x <= start { return x }
  let range = 1 - start
  return start + range * (1 - exp(-(x - start) / range))
}

final class RawToneTests: XCTestCase {
  func testCompensationForFujifilmDynamicRange() {
    XCTAssertEqual(RawTone.compensationEV(developmentDynamicRange: nil), 0)
    XCTAssertEqual(RawTone.compensationEV(developmentDynamicRange: 100), 0)
    XCTAssertEqual(RawTone.compensationEV(developmentDynamicRange: 200), 1, accuracy: 1e-6)
    XCTAssertEqual(RawTone.compensationEV(developmentDynamicRange: 400), 2, accuracy: 1e-6)
  }

  func testShoulderIsIdentityBelowStartSmoothAndBounded() {
    let t = RawTone.shoulderStart
    for i in 0...60 {
      let x = Float(i) / 100
      XCTAssertEqual(RawTone.shoulder(x), x, "midtones stay linear")
    }
    // Slope 1 at the start: no kink where the shoulder begins.
    let e: Float = 1e-3
    XCTAssertEqual((RawTone.shoulder(t + e) - RawTone.shoulder(t)) / e, 1, accuracy: 2e-3)
    var previous: Float = 0
    for i in 0...800 {
      let x = Float(i) / 100
      let y = RawTone.shoulder(x)
      XCTAssertGreaterThanOrEqual(y, previous)
      XCTAssertLessThan(y, 1.0001)
      XCTAssertEqual(y, metalShoulder(x, t), accuracy: 1e-6, "GPU/CPU shoulder in sync")
      previous = y
    }
    XCTAssertGreaterThan(RawTone.shoulder(4), 0.99, "a DR400 highlight rolls off near white")
    XCTAssertLessThan(RawTone.shoulder(1), 0.9, "white is compressed, not clipped")
  }

  func testDevelopAppliesExposureThenShoulder() {
    let out = RawTone.develop(linear: [0.05, 0.1, 0.5], exposureEV: 2)
    XCTAssertEqual(out[0], 0.2, accuracy: 1e-6)
    XCTAssertEqual(out[1], 0.4, accuracy: 1e-6)
    XCTAssertEqual(out[2], RawTone.shoulder(2), accuracy: 1e-6)
    XCTAssertEqual(RawTone.develop(linear: [-0.1], exposureEV: 0), [0])
  }

  // MARK: RAF metadata

  /// Builds a minimal RAF: header, embedded JPEG with Exif → MakerNote → tag 0x1403.
  private func syntheticRAF(dynamicRange: UInt16, bigEndianTIFF: Bool = false) -> Data {
    func u16(_ v: UInt16, _ big: Bool) -> [UInt8] {
      let hi = UInt8(v >> 8)
      let lo = UInt8(v & 0xFF)
      return big ? [hi, lo] : [lo, hi]
    }
    func u32(_ v: UInt32, _ big: Bool) -> [UInt8] {
      let b: [UInt8] = [
        UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)
      ]
      return big ? b : Array(b.reversed())
    }
    let big = bigEndianTIFF
    // TIFF: header(8) IFD0 at 8 (2+12+4=18) → Exif IFD at 26 (18) → MakerNote at 44.
    func entry(_ tag: UInt16, _ type: UInt16, _ count: UInt32, _ value: [UInt8], _ big: Bool) -> [UInt8] {
      var bytes: [UInt8] = []
      bytes.append(contentsOf: u16(tag, big))
      bytes.append(contentsOf: u16(type, big))
      bytes.append(contentsOf: u32(count, big))
      bytes.append(contentsOf: value)
      return bytes
    }
    var tiff: [UInt8] = big ? [0x4D, 0x4D, 0, 42] : [0x49, 0x49, 42, 0]
    tiff.append(contentsOf: u32(8, big))
    tiff.append(contentsOf: u16(1, big))
    tiff.append(contentsOf: entry(0x8769, 4, 1, u32(26, big), big))
    tiff.append(contentsOf: u32(0, big))
    tiff.append(contentsOf: u16(1, big))
    tiff.append(contentsOf: entry(0x927C, 7, 30, u32(44, big), big))
    tiff.append(contentsOf: u32(0, big))
    // Fujifilm MakerNote is always little-endian with offsets from its own start.
    var maker: [UInt8] = Array("FUJIFILM".utf8)
    maker.append(contentsOf: u32(12, false))
    maker.append(contentsOf: u16(1, false))
    var value: [UInt8] = u16(dynamicRange, false)
    value.append(contentsOf: [0, 0])
    maker.append(contentsOf: entry(0x1403, 3, 1, value, false))
    maker.append(contentsOf: u32(0, false))
    tiff.append(contentsOf: maker)
    var app1: [UInt8] = Array("Exif".utf8)
    app1.append(contentsOf: [0, 0])
    app1.append(contentsOf: tiff)
    var jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE1]
    jpeg.append(contentsOf: u16(UInt16(app1.count + 2), true))
    jpeg.append(contentsOf: app1)
    jpeg.append(contentsOf: [0xFF, 0xD9])
    var header: [UInt8] = Array("FUJIFILMCCD-RAW ".utf8)
    header.append(contentsOf: [UInt8](repeating: 0, count: 84 - header.count))
    let offset = UInt32(100)
    header.append(contentsOf: u32(offset, true))
    header.append(contentsOf: u32(UInt32(jpeg.count), true))
    header.append(contentsOf: [UInt8](repeating: 0, count: Int(offset) - header.count))
    header.append(contentsOf: jpeg)
    header.append(contentsOf: [UInt8](repeating: 0, count: 64))
    return Data(header)
  }

  func testReadsDevelopmentDynamicRangeFromRAF() {
    XCTAssertEqual(FujiRAF.developmentDynamicRange(in: syntheticRAF(dynamicRange: 400)), 400)
    XCTAssertEqual(FujiRAF.developmentDynamicRange(in: syntheticRAF(dynamicRange: 200, bigEndianTIFF: true)), 200)
    XCTAssertEqual(FujiRAF.developmentDynamicRange(in: syntheticRAF(dynamicRange: 100)), 100)
  }

  func testRejectsNonRAFAndTruncatedData() {
    XCTAssertNil(FujiRAF.developmentDynamicRange(in: Data()))
    XCTAssertNil(FujiRAF.developmentDynamicRange(in: Data("not a raw file at all".utf8)))
    let raf = syntheticRAF(dynamicRange: 400)
    for length in stride(from: 0, to: raf.count, by: 7) {
      XCTAssertNoThrow(FujiRAF.developmentDynamicRange(in: raf.prefix(length)))
    }
    XCTAssertNil(FujiRAF.developmentDynamicRange(in: syntheticRAF(dynamicRange: 9)), "out of range")
  }

  func testRejectsMetadataOutsideDeclaredBoundsOrWithWrongTypes() {
    let valid = syntheticRAF(dynamicRange: 400)
    // JPEG starts at 100, TIFF at 112, and the MakerNote at TIFF + 44.
    func rejected(_ offset: Int, _ replacement: [UInt8], file: StaticString = #filePath, line: UInt = #line) {
      var data = valid
      data.replaceSubrange(offset..<(offset + replacement.count), with: replacement)
      XCTAssertNil(FujiRAF.developmentDynamicRange(in: data), file: file, line: line)
    }
    rejected(88, [0, 0, 0, 4]) // RAF JPEG length excludes APP1.
    rejected(104, [0, 8]) // APP1 ends before its TIFF header.
    rejected(104, [0xFF, 0xFF]) // APP1 extends beyond the JPEG.
    rejected(114, [0, 0]) // Invalid TIFF magic.
    rejected(144, [12, 0, 0, 0]) // MakerNote length excludes its IFD.
    rejected(144, [0xFF, 0xFF, 0xFF, 0xFF]) // MakerNote extends beyond APP1.
    rejected(164, [0xFF, 0xFF, 0xFF, 0xFF]) // MakerNote IFD offset out of bounds.
    rejected(172, [4, 0]) // DR must be a SHORT, not a LONG.
    rejected(174, [2, 0, 0, 0]) // DR must be a single inline value.
    for length in 0..<186 {
      XCTAssertNil(FujiRAF.developmentDynamicRange(in: valid.prefix(length)), "length \(length)")
    }
  }

  #if !os(Linux)
    @MainActor
    func testPreviewSizeAccountsForCropEditingRetinaAndStraightening() async {
      let model = EditorModel()
      model.sourceAspect = 1.5
      model.updateViewport(CGSize(width: 900, height: 900), scale: 2)
      XCTAssertEqual(model.previewLongEdge, 1800)
      model.state.crop = .init(width: 0.5, height: 1)
      XCTAssertEqual(model.previewLongEdge, 2700)
      model.state.crop = .init(width: 0.1, height: 0.1)
      XCTAssertEqual(model.previewLongEdge, 6144)
      model.cropEditing = true
      XCTAssertEqual(model.previewLongEdge, 1800)
      model.state.straighten = 30
      XCTAssertGreaterThan(model.previewLongEdge, 1800)
      model.pickingNeutral = true
      XCTAssertEqual(model.previewLongEdge, 1800)
      model.dragging = true
      XCTAssertEqual(model.previewLongEdge, 1600)
    }
  #endif

  /// Real camera files, when available locally (set RAWLOOK_SAMPLE_RAFS to a folder of RAFs
  /// named DR<value>-*.raf). Skipped otherwise; the files are too large for the repository.
  func testRealRAFsWhenAvailable() throws {
    guard let folder = ProcessInfo.processInfo.environment["RAWLOOK_SAMPLE_RAFS"] else {
      throw XCTSkip("Set RAWLOOK_SAMPLE_RAFS to check real RAF files.")
    }
    let urls = try FileManager.default.contentsOfDirectory(
      at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil
    ).filter { $0.pathExtension.lowercased() == "raf" }
    XCTAssertFalse(urls.isEmpty)
    for url in urls {
      let expected = Int(url.lastPathComponent.split(separator: "-").first?.dropFirst(2) ?? "")
      XCTAssertEqual(FujiRAF.developmentDynamicRange(in: try Data(contentsOf: url)), expected, url.lastPathComponent)
    }
  }
}
