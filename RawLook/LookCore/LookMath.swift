import Foundation

enum LookMath {
  static func clamp(_ x: Float) -> Float { min(1, max(0, x)) }
  static func decode(_ x: Float) -> Float {
    x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
  }
  static func encode(_ x: Float) -> Float {
    x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
  }
  static func weight(_ s: Float) -> Float {
    let t = clamp((s - 0.03) / 0.15)
    return t * t * (3 - 2 * t)
  }
  static func hue(_ h: Float) -> Float {
    let x = h.truncatingRemainder(dividingBy: 360)
    return x < 0 ? x + 360 : x
  }
  static func hsl(_ rgb: [Float]) -> [Float] {
    let r = rgb[0]
    let g = rgb[1]
    let b = rgb[2]
    let high = max(r, max(g, b))
    let low = min(r, min(g, b))
    let d = high - low
    let l = (high + low) / 2
    guard d > 0 else { return [0, 0, l] }
    let s = d / (1 - abs(2 * l - 1))
    let h: Float = high == r ? (g - b) / d : high == g ? (b - r) / d + 2 : (r - g) / d + 4
    return [hue(h * 60), s, l]
  }
  static func rgb(_ hsl: [Float]) -> [Float] {
    let h = hue(hsl[0]) / 60
    let s = hsl[1]
    let l = hsl[2]
    let c = (1 - abs(2 * l - 1)) * s
    let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
    let m = l - c / 2
    let v: [Float]
    switch h {
    case ..<1: v = [c, x, 0]
    case ..<2: v = [x, c, 0]
    case ..<3: v = [0, c, x]
    case ..<4: v = [0, x, c]
    case ..<5: v = [x, 0, c]
    default: v = [c, 0, x]
    }
    return v.map { $0 + m }
  }
  static func curve(_ x: Float, _ points: [[Float]]) -> Float {
    guard let first = points.first, let last = points.last else { return x }
    if x <= first[0] { return first[1] }
    for i in 1..<points.count where x <= points[i][0] {
      let a = points[i - 1]
      let b = points[i]
      let t = (x - a[0]) / (b[0] - a[0])
      return a[1] + t * (b[1] - a[1])
    }
    return last[1]
  }
  static func sector(_ h: Float, _ anchors: [Preset.Anchor]) -> [Float] {
    guard let first = anchors.first, let last = anchors.last else { return [0, 1, 0] }
    var a = last
    var b = first
    var x = hue(h)
    var left = last.hueDegrees
    var right = first.hueDegrees + 360
    if x < first.hueDegrees { x += 360 }
    for i in 1..<anchors.count where x >= anchors[i - 1].hueDegrees && x < anchors[i].hueDegrees {
      a = anchors[i - 1]
      b = anchors[i]
      left = a.hueDegrees
      right = b.hueDegrees
      break
    }
    let t = (x - left) / (right - left)
    return [
      a.hueDeltaDegrees + t * (b.hueDeltaDegrees - a.hueDeltaDegrees),
      a.saturationMultiplier + t * (b.saturationMultiplier - a.saturationMultiplier),
      a.lightnessAdjustment + t * (b.lightnessAdjustment - a.lightnessAdjustment)
    ]
  }
  static func apply(_ input: [Float], pipeline p: Preset.Pipeline, strength: Float) -> [Float] {
    let original = input.map(clamp)
    var c = original
    for stage in p.executionOrder {
      switch stage {
      case "hsl_sector_adjustments" where p.hslSectorAdjustments.enabled:
        var h = hsl(c)
        let v = sector(h[0], p.hslSectorAdjustments.anchors)
        let w = weight(h[1])
        let d = w * v[2]
        h[0] = hue(h[0] + w * v[0])
        h[1] = clamp(h[1] * (1 + w * (v[1] - 1)))
        h[2] = clamp(h[2] + d * (d >= 0 ? 1 - h[2] : h[2]))
        c = rgb(h)
      case "master_rgb_tone_curve" where p.masterRgbToneCurve.enabled:
        c = c.map { curve($0, p.masterRgbToneCurve.points) }
      case "per_channel_tone_curves" where p.perChannelToneCurves.enabled:
        c = zip(
          c,
          [p.perChannelToneCurves.red, p.perChannelToneCurves.green, p.perChannelToneCurves.blue]
        ).map { curve($0.0, $0.1) }
      case "global_hsl_saturation" where p.globalHslSaturation.enabled:
        var h = hsl(c)
        h[1] = clamp(h[1] * p.globalHslSaturation.multiplier)
        c = rgb(h)
      case "strength_blend_linear_srgb":
        c = zip(original, c).map {
          encode(decode($0.0) * (1 - clamp(strength)) + decode($0.1) * clamp(strength))
        }
      default: break
      }
    }
    return c.map(clamp)
  }
}
