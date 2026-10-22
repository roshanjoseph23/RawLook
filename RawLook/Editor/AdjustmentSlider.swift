import SwiftUI

struct AdjustmentSlider: View {
  let title: String
  @Binding var value: Float
  var range: ClosedRange<Float> = -1...1
  var neutral: Float = 0
  let model: EditorModel
  var body: some View {
    VStack {
      HStack {
        Text(title)
        Spacer()
        Text(value, format: .number.precision(.fractionLength(2))).monospacedDigit()
        Button("Reset \(title)", systemImage: "arrow.counterclockwise") { value = neutral }
          .labelStyle(.iconOnly)
      }
      Slider(
        value: $value, in: range,
        onEditingChanged: { active in if active { model.begin() } else { model.end() } }
      ).accessibilityLabel(title)
    }
  }
}
