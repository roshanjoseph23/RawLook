import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

extension PhotoRenderer {
  static func isRAW(extension suffix: String, type: UTType?) -> Bool {
    type?.conforms(to: .rawImage) == true || OpenablePhotoFile.isRAW(pathExtension: suffix)
  }
  func load(url: URL) throws -> PhotoInfo {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let data = try Data(contentsOf: url)
    let type = UTType(filenameExtension: url.pathExtension)
    return try install(
      data: data, hint: type?.identifier,
      requireRAW: Self.isRAW(extension: url.pathExtension, type: type))
  }
  func load(data: Data, hint: String?, requireRAW: Bool) throws -> PhotoInfo {
    try install(
      data: data, hint: hint,
      requireRAW: requireRAW || hint.flatMap { UTType($0) }?.conforms(to: .rawImage) == true)
  }
  func install(data: Data, hint: String?, requireRAW: Bool) throws -> PhotoInfo {
    // Photos may advertise multiple encodings. Trust the transferred bytes when ImageIO
    // identifies a rendered format, even if the picker also advertised a RAW resource.
    let detectedType = CGImageSourceCreateWithData(data as CFData, nil)
      .flatMap { CGImageSourceGetType($0) }
      .flatMap { UTType($0 as String) }
    let renderedTypes: [UTType] = [.jpeg, .heic, .png, .tiff]
    let isRendered =
      detectedType.map { type in
        !type.conforms(to: .rawImage) && renderedTypes.contains { type.conforms(to: $0) }
      } ?? false
    let needsRAW = !isRendered && (requireRAW || detectedType?.conforms(to: .rawImage) == true)
    let raw =
      needsRAW
      ? CIRAWFilter(imageData: data, identifierHint: detectedType?.identifier ?? hint) : nil
    if needsRAW && raw == nil {
      throw RenderError.message(
        "Apple’s RAW decoder cannot open this file. The camera may not be supported by this OS.")
    }
    let image: CIImage
    if let raw {
      guard let output = raw.outputImage else {
        throw RenderError.message("Apple’s RAW decoder could not develop this camera file.")
      }
      image = output
    } else {
      guard let decoded = CIImage(data: data, options: [.applyOrientationProperty: true]) else {
        throw RenderError.message("This image could not be decoded.")
      }
      image = decoded
    }
    source = image
    asShot = (raw?.neutralTemperature ?? 6500, raw?.neutralTint ?? 0)
    rawFilter = raw
    return PhotoInfo(
      temperature: asShot.0, tint: asShot.1, isRAW: raw != nil, width: image.extent.width,
      height: image.extent.height)
  }
  /// Resolve a picker tap once; subsequent renders use only the saved manual temperature/tint.
  func neutralWhiteBalance(state: EditState, point: [Double]) throws -> (Float, Float) {
    guard let raw = rawFilter, point.count == 2,
      point.allSatisfy({ $0.isFinite && (0...1).contains($0) })
    else { throw RenderError.message("Choose a neutral patch on a RAW image.") }
    _ = try baseline(state, maxSize: nil)
    raw.scaleFactor = 1
    guard let output = raw.outputImage else {
      throw RenderError.message("RAW development failed for this camera.")
    }
    // The picker shows the un-rotated, un-cropped RAW-stage image. Its normalized
    // coordinates are y-up (Core Image), mapped into the un-scaled output extent.
    let extent = output.extent
    raw.neutralLocation = CGPoint(
      x: extent.minX + point[0] * extent.width,
      y: extent.minY + point[1] * extent.height)
    let temperature = raw.neutralTemperature
    let tint = raw.neutralTint
    guard temperature.isFinite, tint.isFinite else {
      throw RenderError.message("Neutral sampling failed.")
    }
    return (temperature, tint)
  }
  /// Develop the photo. `shift` is the preset's white-balance offset (already scaled by the
  /// look strength); it sits on top of the per-photo as-shot or manual white balance.
  func baseline(_ state: EditState, maxSize: CGFloat?, shift: WhiteBalanceShift = .zero) throws
    -> CIImage
  {
    guard let source else { throw RenderError.message("Open a photo first.") }
    var image = source
    if let raw = rawFilter {
      raw.exposure = state.exposure
      raw.scaleFactor =
        maxSize.map { Float(min(1, $0 / max(image.extent.width, image.extent.height))) } ?? 1
      // Restore file values before applying each immutable edit snapshot.
      raw.neutralTemperature = asShot.0
      raw.neutralTint = asShot.1
      if state.whiteBalanceMode == .manual {
        raw.neutralTemperature = state.temperature
        raw.neutralTint = state.tint
      }
      if !shift.isZero {
        raw.neutralTemperature = shift.kelvin(from: raw.neutralTemperature)
        raw.neutralTint = shift.tint(from: raw.neutralTint)
      }
      guard let output = raw.outputImage else {
        throw RenderError.message("RAW development failed for this camera.")
      }
      image = output
    } else {
      if state.exposure != 0 {
        let filter = CIFilter.exposureAdjust()
        filter.inputImage = image
        filter.ev = state.exposure
        image = filter.outputImage ?? image
      }
      if state.whiteBalanceMode == .manual {
        let filter = CIFilter.temperatureAndTint()
        filter.inputImage = image
        filter.neutral = CIVector(x: 6500, y: 0)
        filter.targetNeutral = CIVector(x: CGFloat(state.temperature), y: CGFloat(state.tint))
        image = filter.outputImage ?? image
      }
      if let gains = state.neutralGains {
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: CGFloat(gains[0]), y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: CGFloat(gains[1]), z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: CGFloat(gains[2]), w: 0)
        image = filter.outputImage ?? image
      }
      if !shift.isZero {
        // Rendered files carry no RAW white point, so shift relative to D65 in linear sRGB
        // (the same gains the CPU reference LookMath.develop uses).
        let gains = shift.linearGains()
        let filter = CIFilter.colorMatrix()
        filter.inputImage = image
        filter.rVector = CIVector(x: CGFloat(gains[0]), y: 0, z: 0, w: 0)
        filter.gVector = CIVector(x: 0, y: CGFloat(gains[1]), z: 0, w: 0)
        filter.bVector = CIVector(x: 0, y: 0, z: CGFloat(gains[2]), w: 0)
        image = filter.outputImage ?? image
      }
    }
    image = image.transformed(
      by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    if let maxSize, max(image.extent.width, image.extent.height) > maxSize {
      let scale = maxSize / max(image.extent.width, image.extent.height)
      let filter = CIFilter.lanczosScaleTransform()
      filter.inputImage = image
      filter.scale = Float(scale)
      filter.aspectRatio = 1
      image = filter.outputImage ?? image
    }
    return image
  }

}
