import SwiftUI

struct EditorInspector: View {
  @Bindable var model: EditorModel
  var body: some View {
    Form {
      Section("RAW development · per photo") {
        Text(model.isRAW ? "Camera RAW baseline" : "Linear image baseline").font(.caption)
          .foregroundStyle(.secondary)
        AdjustmentSlider(
          title: "Exposure EV", value: $model.state.exposure, range: -5...5, model: model)
        Picker("White balance", selection: $model.whiteBalanceSelection) {
          Text("As Shot").tag(WhiteBalanceMode.asShot)
          Text("Temperature / Tint").tag(WhiteBalanceMode.manual)
        }
        AdjustmentSlider(
          title: "Temperature K", value: $model.temperature, range: 2000...15000, neutral: 6500,
          model: model)
        AdjustmentSlider(title: "Tint", value: $model.tint, range: -150...150, model: model)
        Button("Pick neutral patch", systemImage: "eyedropper", action: model.startNeutralPicking)
        Button("Reset to As Shot", action: model.resetWB)
        Toggle("Show render info", isOn: $model.showRenderInfo)
      }
      Section("Preset") {
        Picker("Look", selection: $model.selectedPresetID) {
          Text("No look").tag(String?.none)
          ForEach(model.library.presets) { preset in Text(preset.name).tag(Optional(preset.id)) }
        }
        AdjustmentSlider(
          title: "Strength", value: $model.state.strength, range: 0...1, neutral: 1, model: model)
      }
      if !model.library.warnings.isEmpty {
        Section("Preset warnings") {
          ForEach(model.library.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
        }
      }
      Section("Adjustments") {
        ForEach(Adjustment.allCases, id: \.self) { key in
          AdjustmentSlider(
            title: key.displayName, value: $model[adjustment: key], range: key.range,
            neutral: key.neutralValue, model: model)
        }
        Button("Reset All Adjustments") { model.state.adjustments = [:] }
      }
      Section("Tone curves · replaces preset curves") { CurveEditor(model: model) }
      Section("Crop & rotate") { GeometryControls(model: model) }
      Section("Export") {
        Picker("Format", selection: $model.format) {
          ForEach(ExportFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
        if model.format != .tiff16 {
          Slider(value: $model.quality, in: 0.1...1) { Text("Quality") }
          Text("Quality \(model.quality, format: .percent)")
        }
        Picker("Color profile", selection: $model.colorProfile) {
          Text("sRGB").tag(ColorProfile.sRGB)
          Text("Display P3").tag(ColorProfile.displayP3)
        }
        Button("Export to Files", systemImage: "square.and.arrow.up") { model.export() }.disabled(
          !model.loaded || model.busy)
        #if os(iOS)
          Button("Save to Photos", systemImage: "photo.badge.plus") { model.export(photos: true) }
            .disabled(!model.loaded || model.busy)
        #endif
        Text("Exports a new file at full resolution.").font(.caption)
      }
    }
    .formStyle(.grouped)
  }
}
