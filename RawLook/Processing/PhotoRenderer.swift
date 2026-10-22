import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

actor PhotoRenderer {
  let linearSpace =
    CGColorSpace(name: CGColorSpace.extendedLinearSRGB) ?? CGColorSpaceCreateDeviceRGB()
  lazy var context = CIContext(options: [
    .workingColorSpace: linearSpace, .workingFormat: CIFormat.RGBAf.rawValue
  ])
  var rawFilter: CIRAWFilter?
  var source: CIImage?
  var asShot: (Float, Float) = (6500, 0)
  var kernel: CIKernel?
  var shoulderKernel: CIColorKernel?
  /// Fujifilm DevelopmentDynamicRange of the open RAF (100/200/400), when present.
  var dynamicRange: Int?
  /// The camera's DR push, applied as part of the as-shot RAW development (not the slider).
  var compensationEV: Float = 0

  /// Preview taps are normalized bottom-left coordinates in the uncropped baseline.
  func neutralGains(state: EditState, point: [Double]) throws -> [Float] {
    var clean = state
    clean.neutralGains = nil
    let image = try baseline(clean, maxSize: nil)
    let e = image.extent
    let area = CGRect(x: point[0] * e.width - 2, y: point[1] * e.height - 2, width: 5, height: 5)
      .intersection(e)
    let filter = CIFilter.areaAverage()
    filter.inputImage = image
    filter.extent = area
    guard let avg = filter.outputImage else {
      throw RenderError.message("Neutral sampling failed.")
    }
    var pixel = [Float](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { buffer in
      if let address = buffer.baseAddress {
        context.render(
          avg, toBitmap: address, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
          format: .RGBAf, colorSpace: linearSpace)
      }
    }
    let target = (pixel[0] + pixel[1] + pixel[2]) / 3
    guard pixel.prefix(3).allSatisfy({ $0 > 0.00001 && $0.isFinite }) else {
      throw RenderError.message("Choose a brighter neutral patch.")
    }
    return pixel.prefix(3).map { min(8, max(0.125, target / $0)) }
  }
  /// Develop in linear sRGB, apply the creative look and adjustments, then crop.
  func renderImage(
    state: EditState, preset: Preset?, size: CGFloat?, before: Bool, cropEditing: Bool = false
  ) throws -> CIImage {
    let shift =
      before
      ? WhiteBalanceShift.zero
      : (preset?.estimatedCreativePipeline.whiteBalanceShift ?? .zero).scaled(by: state.strength)
    var image = try baseline(state, maxSize: size, shift: shift)
    if !before {
      if let preset { image = try look(image, preset: preset, state: state) }
      image = adjusted(image, state)
    }
    var geometryState = state
    if cropEditing { geometryState.crop = .init() }
    return geometry(image, geometryState)
  }
  func preview(
    state: EditState, preset: Preset?, size: CGFloat, before: Bool, cropEditing: Bool,
    neutralEditing: Bool
  ) throws -> (image: CGImage, info: [String]) {
    try Task.checkCancellation()
    let image: CIImage
    if neutralEditing {
      image = try baseline(state, maxSize: size)
    } else {
      image = try renderImage(
        state: state, preset: preset, size: size, before: before, cropEditing: cropEditing)
    }
    guard
      let cg = context.createCGImage(
        image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
      )
    else { throw RenderError.message("Preview rendering failed.") }
    try Task.checkCancellation()
    return (cg, renderInfo(
      state: state, preset: preset, before: before, previewWidth: cg.width,
      previewHeight: cg.height, requested: size))
  }

}
