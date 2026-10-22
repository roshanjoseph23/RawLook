import SwiftUI

struct CurveEditor: View {
  @Bindable var model: EditorModel
  @State private var selectedChannel: CurveChannel = .master
  private var channel: Int { selectedChannel.rawValue }
  @State private var selected: Int?
  var body: some View {
    VStack {
      Picker("Channel", selection: $selectedChannel) {
        ForEach(CurveChannel.allCases, id: \.self) { Text($0.displayName).tag($0) }
      }.pickerStyle(.segmented)
      if model.state.curves.count == 4 {
        GeometryReader { proxy in
          CurveCanvas(points: model.state.curves[channel], histogram: model.histogram)
            .contentShape(.rect)
            .gesture(
              DragGesture(minimumDistance: 0).onChanged { value in
                move(value, size: proxy.size)
              }.onEnded { value in
                removeIfOutside(value.location, size: proxy.size)
                selected = nil
                model.end()
              }
            )
            .accessibilityLabel(
              "\(selectedChannel.displayName) tone curve. Drag points or tap to add; drag an interior point outside to remove."
            )
        }.frame(height: 180)
        ForEach(
          Array(zip(model.state.curveIDs[channel], model.state.curves[channel].indices)), id: \.0
        ) { pair in
          CurvePointRow(model: model, channel: channel, index: pair.1)
        }
        Button("Reset \(selectedChannel.displayName) to Preset") { model.resetCurve(channel) }
        Button("Reset All Curves to Preset") { model.resetCurve(nil) }
      } else {
        Text("Select a preset to edit its curves.")
      }
    }
  }
  private func move(_ value: DragGesture.Value, size: CGSize) {
    let x = LookMath.clamp(Float(value.location.x / size.width))
    let y = LookMath.clamp(Float(1 - value.location.y / size.height))
    if selected == nil {
      model.begin()
      let points = model.state.curves[channel]
      func distance(to point: [Float]) -> CGFloat {
        let dx = CGFloat(point[0]) * size.width - value.startLocation.x
        let dy = CGFloat(1 - point[1]) * size.height - value.startLocation.y
        return hypot(dx, dy)
      }
      let distances = points.map { distance(to: $0) }
      let nearest = distances.indices.min(by: { distances[$0] < distances[$1] })
      if let nearest, distances[nearest] < 24 {
        selected = nearest
      } else if points.count < 16, x > points[0][0] + 0.005,
        x < points[points.count - 1][0] - 0.005, !points.contains(where: { abs($0[0] - x) < 0.005 }) {
        let index = points.firstIndex(where: { $0[0] > x }) ?? points.count - 1
        model.state.curves[channel].insert([x, y], at: index)
        model.state.curveIDs[channel].insert(UUID(), at: index)
        selected = index
      }
    }
    guard let index = selected else { return }
    let points = model.state.curves[channel]
    if index > 0 && index < points.count - 1 {
      model.state.curves[channel][index][0] = min(
        points[index + 1][0] - 0.001, max(points[index - 1][0] + 0.001, x))
    }
    model.state.curves[channel][index][1] = y
  }
  private func removeIfOutside(_ location: CGPoint, size: CGSize) {
    if let index = selected, index > 0, index < model.state.curves[channel].count - 1,
      !CGRect(origin: .zero, size: size).insetBy(dx: -25, dy: -25).contains(location) {
      model.removeCurvePoint(channel: channel, index: index)
    }
  }
}
