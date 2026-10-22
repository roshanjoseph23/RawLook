import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

extension PhotoRenderer {
  /// Straighten inside safe original-aspect bounds, then rotate, flip and crop in bottom-left coordinates.
  func geometry(_ image: CIImage, _ state: EditState) -> CIImage {
    let e = image.extent
    let angle = state.straighten * .pi / 180
    var output = image.transformed(by: CGAffineTransform(translationX: -e.midX, y: -e.midY))
      .transformed(by: CGAffineTransform(rotationAngle: angle))
    let safe = CropGeometry.inscribed(width: e.width, height: e.height, radians: angle)
    output = output.cropped(
      to: CGRect(x: -safe.width / 2, y: -safe.height / 2, width: safe.width, height: safe.height))
    output = output.transformed(
      by: CGAffineTransform(rotationAngle: Double(state.quarterTurns) * Double.pi / 2))
    output = output.transformed(
      by: CGAffineTransform(scaleX: state.flipHorizontal ? -1 : 1, y: state.flipVertical ? -1 : 1))
    let bounds = output.extent
    let c = CropGeometry.clamp(state.crop)
    output = output.cropped(
      to: CGRect(
        x: bounds.minX + c.x * bounds.width, y: bounds.minY + c.y * bounds.height,
        width: c.width * bounds.width, height: c.height * bounds.height))
    return output.transformed(
      by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY))
  }

}
