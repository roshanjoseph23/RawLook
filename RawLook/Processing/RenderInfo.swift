import CoreImage

extension PhotoRenderer {
  /// A compact description of what the last preview actually used, shown in the on-screen
  /// render-info overlay so a screenshot tells us exactly how the photo was developed.
  func renderInfo(state: EditState, preset: Preset?, before: Bool, previewWidth: Int, previewHeight: Int, requested: CGFloat) -> [String] {
    var lines: [String] = []
    if let preset {
      let shift = preset.estimatedCreativePipeline.whiteBalanceShift ?? .zero
      lines.append(
        "Look: \(preset.id) v\(preset.presetVersion ?? "–") · strength \(fmt(state.strength))"
          + " · WB shift \(fmt(shift.temperatureShiftMireds)) mired / \(fmt(shift.tintShift))"
          + (before ? " · BEFORE (look off)" : ""))
    } else {
      lines.append("Look: none" + (before ? " · BEFORE" : ""))
    }
    if let raw = rawFilter {
      let dr = dynamicRange.map { "DR\($0)" } ?? "DR n/a"
      lines.append(
        "RAW: \(dr) push \(fmt(compensationEV)) EV · slider \(fmt(state.exposure)) EV"
          + " · baseline \(fmt(raw.baselineExposure)) EV · boost \(fmt(raw.boostAmount))"
          + " · shadow boost \(fmt(raw.boostShadowAmount))"
          + (raw.isLocalToneMapSupported ? " · local TM \(fmt(raw.localToneMapAmount))" : ""))
      lines.append(
        "Lens corr: \(raw.isLensCorrectionSupported ? (raw.isLensCorrectionEnabled ? "on" : "off") : "unsupported")"
          + " · NR lum \(fmt(raw.luminanceNoiseReductionAmount)) col \(fmt(raw.colorNoiseReductionAmount))"
          + " · sharp \(fmt(raw.sharpnessAmount)) detail \(fmt(raw.detailAmount))"
          + " · WB \(Int(raw.neutralTemperature)) K / \(fmt(raw.neutralTint))")
      lines.append(
        "Decode scale \(fmt(raw.scaleFactor)) · preview \(previewWidth)×\(previewHeight) px"
          + " (requested \(Int(requested)) px)")
    } else {
      lines.append("Rendered image · preview \(previewWidth)×\(previewHeight) px (requested \(Int(requested)) px)")
    }
    return lines
  }

  private func fmt(_ value: Float) -> String { String(format: "%+.2f", value) }
}
