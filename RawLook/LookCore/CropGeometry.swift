import Foundation

enum CropGeometry {
  struct Rect: Codable, Sendable, Equatable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1
  }
  // Largest centered rectangle with the original aspect inside a rotated image.
  static func inscribed(width: Double, height: Double, radians: Double) -> (
    width: Double, height: Double
  ) {
    let c = abs(cos(radians))
    let s = abs(sin(radians))
    let scale = min(width / (width * c + height * s), height / (width * s + height * c))
    return (width * scale, height * scale)
  }
  static func clamp(_ rect: Rect) -> Rect {
    let w = min(1, max(0.01, rect.width))
    let h = min(1, max(0.01, rect.height))
    return Rect(x: min(1 - w, max(0, rect.x)), y: min(1 - h, max(0, rect.y)), width: w, height: h)
  }
  static func constrainAspect(
    _ rect: Rect, original: Rect, ratio: Double, left: Bool, bottom: Bool, vertical: Bool
  ) -> Rect {
    guard ratio.isFinite, ratio > 0 else { return clamp(rect) }
    var w = vertical ? rect.height * ratio : rect.width
    w = max(0.01, min(w, min(1, ratio)))
    var h = w / ratio
    let anchorX = left ? original.x + original.width : original.x
    let anchorY = bottom ? original.y + original.height : original.y
    let availableW = left ? anchorX : 1 - anchorX
    let availableH = bottom ? anchorY : 1 - anchorY
    let scale = min(1, min(availableW / w, availableH / h))
    w *= scale
    h *= scale
    return Rect(
      x: left ? anchorX - w : anchorX, y: bottom ? anchorY - h : anchorY, width: w, height: h)
  }
  static func fit(aspect: Double, imageAspect: Double) -> Rect {
    guard aspect > 0, imageAspect > 0 else { return Rect() }
    let w = min(1, aspect / imageAspect)
    let h = min(1, imageAspect / aspect)
    return Rect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
  }
}
