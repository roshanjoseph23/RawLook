import Foundation

/// Minimal, bounds-checked reader for the Fujifilm metadata RawLook needs from a RAF file.
///
/// Fujifilm's DR200/DR400 modes underexpose the sensor by one or two stops to protect
/// highlights and push the image back up in the camera's own JPEG. Apple's RAW decoder does not
/// apply that push, so RAWs shot in DR modes develop one or two stops too dark.
/// Layout: "FUJIFILMCCD-RAW" header; big-endian JPEG offset/length at bytes 84/88; the JPEG's
/// APP1 Exif → Exif IFD → MakerNote ("FUJIFILM" + little-endian IFD); tag 0x1403 is
/// DevelopmentDynamicRange (100, 200, 400...).
enum FujiRAF {
  static let developmentDynamicRangeTag: UInt16 = 0x1403

  static func developmentDynamicRange(in data: Data) -> Int? {
    let bytes = [UInt8](data.prefix(16 * 1024 * 1024))
    guard bytes.count >= 92, Array(bytes[0..<15]) == Array("FUJIFILMCCD-RAW".utf8) else {
      return nil
    }
    let jpegOffset = Int(be32(bytes, 84))
    let jpegLength = Int(be32(bytes, 88))
    let jpegEnd = min(bytes.count, jpegOffset + jpegLength)
    guard jpegOffset >= 92, jpegOffset + 4 <= jpegEnd, bytes[jpegOffset] == 0xFF,
      bytes[jpegOffset + 1] == 0xD8
    else { return nil }
    // Walk JPEG markers to APP1 Exif.
    var i = jpegOffset + 2
    while i + 4 <= jpegEnd, bytes[i] == 0xFF {
      let marker = bytes[i + 1]
      let length = Int(be16(bytes, i + 2))
      guard length >= 2, i + 2 + length <= jpegEnd else { return nil }
      if marker == 0xE1, length >= 8, Array(bytes[(i + 4)..<(i + 10)]) == [0x45, 0x78, 0x69, 0x66, 0, 0] {
        return exifDynamicRange(bytes, tiff: i + 10, end: i + 2 + length)
      }
      if marker == 0xDA { return nil }
      i += 2 + length
    }
    return nil
  }

  private static func exifDynamicRange(_ b: [UInt8], tiff: Int, end: Int) -> Int? {
    guard tiff + 8 <= end else { return nil }
    let little: Bool
    switch (b[tiff], b[tiff + 1]) {
    case (0x49, 0x49): little = true
    case (0x4D, 0x4D): little = false
    default: return nil
    }
    func u16(_ at: Int) -> UInt16? { at + 2 <= end ? (little ? le16(b, at) : be16(b, at)) : nil }
    func u32(_ at: Int) -> UInt32? { at + 4 <= end ? (little ? le32(b, at) : be32(b, at)) : nil }
    func find(_ ifd: Int, _ tag: UInt16) -> Int? {
      guard let count = u16(ifd) else { return nil }
      for n in 0..<Int(count) {
        let entry = ifd + 2 + n * 12
        guard let t = u16(entry) else { return nil }
        if t == tag { return entry }
      }
      return nil
    }
    guard u16(tiff + 2) == 42,
      let ifd0 = u32(tiff + 4).map({ tiff + Int($0) }),
      let exifEntry = find(ifd0, 0x8769),
      u16(exifEntry + 2) == 4, u32(exifEntry + 4) == 1,
      let exifOffset = u32(exifEntry + 8),
      let makerEntry = find(tiff + Int(exifOffset), 0x927C),
      u16(makerEntry + 2) == 7, let makerLength = u32(makerEntry + 4),
      let makerOffset = u32(makerEntry + 8)
    else { return nil }
    let maker = tiff + Int(makerOffset)
    // Fujifilm MakerNote: "FUJIFILM", then a little-endian offset (from the note start) to its IFD.
    let makerEnd = maker + Int(makerLength)
    guard makerLength >= 12, makerEnd <= end, Array(b[maker..<(maker + 8)]) == Array("FUJIFILM".utf8) else {
      return nil
    }
    let ifd = maker + Int(le32(b, maker + 8))
    guard ifd >= maker + 12, ifd + 2 <= makerEnd else { return nil }
    let count = Int(le16(b, ifd))
    for n in 0..<count {
      let entry = ifd + 2 + n * 12
      guard entry + 12 <= makerEnd else { return nil }
      if le16(b, entry) == developmentDynamicRangeTag {
        guard le16(b, entry + 2) == 3, le32(b, entry + 4) == 1 else { return nil }
        let value = Int(le16(b, entry + 8))
        return (100...1600).contains(value) ? value : nil
      }
    }
    return nil
  }

  private static func be16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) << 8 | UInt16(b[i + 1]) }
  private static func be32(_ b: [UInt8], _ i: Int) -> UInt32 {
    UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
  }
  private static func le16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
  private static func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
    UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
  }
}

/// RawLook's own RAW tone rendering, shared by the GPU kernel (`rawShoulder` in Look.metal)
/// and the CPU reference. RAWs are decoded scene-linear (CIRAWFilter boostAmount 0, so no
/// Apple contrast curve crushing shadows), pushed by the camera's DR compensation, then only a
/// smooth highlight shoulder keeps pushed highlights from clipping. Midtones stay linear.
enum RawTone {
  /// Linear value where the shoulder starts (about 0.80 encoded sRGB).
  static let shoulderStart: Float = 0.6

  /// Stops to add for the camera's DR mode: DR200 → +1 EV, DR400 → +2 EV.
  static func compensationEV(developmentDynamicRange dr: Int?) -> Float {
    guard let dr, dr > 100 else { return 0 }
    return log2(Float(dr) / 100)
  }

  /// CPU reference for the RAW stage: linear camera RGB scaled by the as-shot DR push plus the
  /// exposure slider (CIRAWFilter exposure), then the highlight shoulder. Output stays linear.
  static func develop(linear: [Float], exposureEV: Float) -> [Float] {
    let scale = exp2(exposureEV)
    return linear.map { shoulder(max(0, $0) * scale) }
  }

  /// Identity below `start`; above it, an exponential shoulder with slope 1 at `start` that
  /// approaches 1.0, so pushed highlights roll off instead of clipping.
  static func shoulder(_ x: Float, start: Float = shoulderStart) -> Float {
    guard x > start else { return x }
    let range = 1 - start
    return start + range * (1 - exp(-(x - start) / range))
  }
}
