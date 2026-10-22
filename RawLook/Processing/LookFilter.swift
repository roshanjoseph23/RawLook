import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

extension PhotoRenderer {
  func look(_ image: CIImage, preset: Preset, state: EditState) throws -> CIImage {
    if kernel == nil {
      guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib") else {
        throw RenderError.message("Missing Core Image Metal library. Check Metal build flags.")
      }
      kernel = try CIKernel(functionName: "rawLook", fromMetalLibraryData: Data(contentsOf: url))
    }
    let p = preset.estimatedCreativePipeline
    let curves =
      state.curves.count == 4
      ? state.curves
      : [
        p.masterRgbToneCurve.points, p.perChannelToneCurves.red, p.perChannelToneCurves.green,
        p.perChannelToneCurves.blue
      ]
    _ = try preset.validate()
    for curve in curves { try Preset.validateCurve(curve) }
    let pixels = try LookTable.pack(anchors: p.hslSectorAdjustments.anchors, curves: curves)
    let data = pixels.withUnsafeBytes { Data($0) }
    // This is numeric data, not color: nil disables color matching of the table.
    let table = CIImage(
      bitmapData: data, bytesPerRow: 16 * 4 * MemoryLayout<Float>.size,
      size: CGSize(width: 16, height: 5), format: .RGBAf, colorSpace: nil
    ).samplingNearest()
    let has: (String, Bool) -> CGFloat = { p.executionOrder.contains($0) && $1 ? 1 : 0 }
    let counts = CIVector(
      x: CGFloat(curves[0].count), y: CGFloat(curves[1].count), z: CGFloat(curves[2].count),
      w: CGFloat(curves[3].count))
    let flags = CIVector(
      x: has("hsl_sector_adjustments", p.hslSectorAdjustments.enabled),
      y: has("master_rgb_tone_curve", p.masterRgbToneCurve.enabled),
      z: has("per_channel_tone_curves", p.perChannelToneCurves.enabled),
      w: has("global_hsl_saturation", p.globalHslSaturation.enabled))
    let options = CIVector(
      x: CGFloat(p.hslSectorAdjustments.anchors.count),
      y: CGFloat(p.globalHslSaturation.multiplier), z: CGFloat(state.strength),
      w: has("strength_blend_linear_srgb", true))
    guard
      let output = kernel?.apply(
        extent: image.extent, roiCallback: { index, rect in index == 1 ? table.extent : rect },
        arguments: [image, table, counts, flags, options])
    else { throw RenderError.message("The GPU look could not be rendered.") }
    return output
  }

}
