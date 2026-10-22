import SwiftUI

struct CurveEditor: View {
  @Bindable var model: EditorModel
  @State private var selectedChannel: CurveChannel = .master
  /// The point being dragged, tracked by stable id so insertions and removals cannot shift it.
  @State private var selectedPoint: UUID?
  @State private var dragActive = false
  private var channel: Int { selectedChannel.rawValue }
  var body: some View {
    VStack {
      Picker("Channel", selection: $selectedChannel) {
        ForEach(CurveChannel.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }.pickerStyle(.segmented)
      if model.state.curves.count == CurveChannel.allCases.count, model.state.hasCurve(channel) {
        GeometryReader { proxy in
          CurveCanvas(points: model.state.curvePoints(channel), histogram: model.histogram)
            .contentShape(.rect)
            .gesture(
              DragGesture(minimumDistance: 0).onChanged { value in
                move(value, size: proxy.size)
              }.onEnded { value in
                removeIfOutside(value.location, size: proxy.size)
                finishDrag()
              }
            )
            .accessibilityLabel(
              "\(selectedChannel.displayName) tone curve. Drag points or tap to add; drag an interior point outside to remove."
            )
        }.frame(height: 180)
        ForEach(model.state.curveItems(channel)) { item in
          CurvePointRow(
            item: item,
            onAdjust: { delta in model.adjustCurvePoint(channel: channel, id: item.id, by: delta) },
            onRemove: { model.removeCurvePoint(channel: channel, id: item.id) })
        }
        Button("Reset \(selectedChannel.displayName) to Preset") { resetCurve(channel) }
        Button("Reset All Curves to Preset") { resetCurve(nil) }
      } else {
        Text("Select a preset to edit its curves.")
      }
    }
    .onChange(of: selectedChannel) { finishDrag() }
    .onChange(of: model.state.curveIDs) {
      if let id = selectedPoint, model.state.curvePosition(channel: channel, id: id) == nil {
        selectedPoint = nil
      }
    }
  }
  private func resetCurve(_ channel: Int?) {
    finishDrag()
    model.resetCurve(channel)
  }
  private func finishDrag() {
    selectedPoint = nil
    if dragActive {
      dragActive = false
      model.end()
    }
  }
  private func move(_ value: DragGesture.Value, size: CGSize) {
    guard size.width > 0, size.height > 0, model.state.hasCurve(channel) else { return }
    let x = LookMath.clamp(Float(value.location.x / size.width))
    let y = LookMath.clamp(Float(1 - value.location.y / size.height))
    if !dragActive {
      dragActive = true
      model.begin()
      selectedPoint =
        model.state.nearestCurvePoint(
          channel: channel,
          location: (Double(value.startLocation.x), Double(value.startLocation.y)),
          scale: (Double(size.width), Double(size.height)), radius: 24)
        ?? model.state.insertCurvePoint(channel: channel, input: x, output: y)
    }
    guard let id = selectedPoint else { return }
    model.state.moveCurvePoint(channel: channel, id: id, input: x, output: y)
  }
  private func removeIfOutside(_ location: CGPoint, size: CGSize) {
    guard let id = selectedPoint,
      !CGRect(origin: .zero, size: size).insetBy(dx: -25, dy: -25).contains(location)
    else { return }
    model.removeCurvePoint(channel: channel, id: id)
  }
}
