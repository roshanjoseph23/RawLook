import SwiftUI

struct GeometryControls: View {
  @Bindable var model: EditorModel
  var body: some View {
    Toggle("Edit crop on preview", isOn: $model.cropEditing)
    Picker("Aspect", selection: $model.cropAspectSelection) {
      ForEach(CropAspect.allCases, id: \.self) { Text($0.displayName).tag($0) }
    }
    Toggle("Portrait aspect", isOn: $model.cropPortraitSelection)
    Text("Straighten \(model.state.straighten, format: .number.precision(.fractionLength(1)))°")
    Slider(
      value: $model.state.straighten, in: -45...45,
      onEditingChanged: { if $0 { model.begin() } else { model.end() } }
    ).accessibilityLabel("Straighten")
    HStack {
      Button("Rotate left", systemImage: "rotate.left") {
        model.state.quarterTurns -= 1
        model.fitCrop()
      }
      Button("Rotate right", systemImage: "rotate.right") {
        model.state.quarterTurns += 1
        model.fitCrop()
      }
    }
    Toggle("Flip horizontal", isOn: $model.state.flipHorizontal)
    Toggle("Flip vertical", isOn: $model.state.flipVertical)
    Button("Reset Geometry", action: model.resetGeometry)
    Text(
      "Drag the crop to move it; drag a corner or edge to resize. Straightening constrains the crop inside the image."
    ).font(.caption)
  }
}
