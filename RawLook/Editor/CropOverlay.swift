import SwiftUI

struct CropOverlay: View {
  @Bindable var model: EditorModel
  @State private var start: CropGeometry.Rect?
  @State private var handle = 0
  var body: some View {
    GeometryReader { proxy in
      let crop = model.state.crop
      let rect = CGRect(
        x: crop.x * proxy.size.width, y: (1 - crop.y - crop.height) * proxy.size.height,
        width: crop.width * proxy.size.width, height: crop.height * proxy.size.height)
      ZStack {
        Path { path in
          path.addRect(CGRect(origin: .zero, size: proxy.size))
          path.addRect(rect)
        }.fill(.black.opacity(0.5), style: FillStyle(eoFill: true))
        Rectangle().stroke(.white, lineWidth: 2).frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
        ForEach(1..<9) { index in
          let point = position(index, rect: rect)
          Circle().fill(.white).frame(width: 12, height: 12).position(point)
        }
      }
      .contentShape(.rect)
      .gesture(
        DragGesture().onChanged { value in
          if start == nil {
            start = crop
            handle = nearest(value.startLocation, rect: rect)
            model.begin()
          }
          guard var next = start else { return }
          let dx = value.translation.width / proxy.size.width
          let dy = -value.translation.height / proxy.size.height
          if handle == 0 {
            next.x += dx
            next.y += dy
          } else {
            if [1, 4, 7].contains(handle) {
              next.x += dx
              next.width -= dx
            }
            if [3, 6, 8].contains(handle) { next.width += dx }
            if [1, 2, 3].contains(handle) { next.height += dy }
            if [7, 5, 8].contains(handle) {
              next.y += dy
              next.height -= dy
            }
          }
          if let pixelRatio = model.state.cropAspect.ratio(
            imageAspect: model.imageAspect, portrait: model.state.cropPortrait), handle != 0,
            let initial = start {
            next = CropGeometry.constrainAspect(
              next, original: initial, ratio: pixelRatio / model.imageAspect,
              left: [1, 4, 7].contains(handle), bottom: [7, 5, 8].contains(handle),
              vertical: handle == 2 || handle == 5)
          }
          model.state.crop = CropGeometry.clamp(next)
        }.onEnded { _ in
          start = nil
          model.end()
        }
      )
      .accessibilityLabel("Crop rectangle")
      .accessibilityHint("Use the aspect picker to select a centered crop or drag edges to resize.")
    }
  }
  private func position(_ index: Int, rect: CGRect) -> CGPoint {
    switch index {
    case 1: CGPoint(x: rect.minX, y: rect.minY)
    case 2: CGPoint(x: rect.midX, y: rect.minY)
    case 3: CGPoint(x: rect.maxX, y: rect.minY)
    case 4: CGPoint(x: rect.minX, y: rect.midY)
    case 5: CGPoint(x: rect.midX, y: rect.maxY)
    case 6: CGPoint(x: rect.maxX, y: rect.midY)
    case 7: CGPoint(x: rect.minX, y: rect.maxY)
    default: CGPoint(x: rect.maxX, y: rect.maxY)
    }
  }
  private func nearest(_ point: CGPoint, rect: CGRect) -> Int {
    (1..<9).first {
      hypot(position($0, rect: rect).x - point.x, position($0, rect: rect).y - point.y) < 28
    } ?? 0
  }
}
