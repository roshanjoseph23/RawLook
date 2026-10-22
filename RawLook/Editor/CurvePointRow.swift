import SwiftUI

struct CurvePointRow: View {
  let model: EditorModel
  let channel: Int
  let index: Int
  var body: some View {
    HStack {
      Text("Point \(index+1)")
      Spacer()
      Text(model.state.curves[channel][index][1], format: .number.precision(.fractionLength(2)))
      if index > 0 && index < model.state.curves[channel].count - 1 {
        Button("Remove point \(index+1)", systemImage: "minus.circle", action: remove).labelStyle(
          .iconOnly)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAdjustableAction { direction in
      let delta: Float = direction == .increment ? 0.01 : -0.01
      model.state.curves[channel][index][1] = LookMath.clamp(
        model.state.curves[channel][index][1] + delta)
    }
  }
  private func remove() { model.removeCurvePoint(channel: channel, index: index) }
}
