import SwiftUI

struct PreviewView: View {
  @Bindable var model: EditorModel
  @GestureState private var comparing = false
  @Environment(\.displayScale) private var displayScale
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black.opacity(0.9)
        if let image = model.preview {
          let scale = min(
            proxy.size.width / CGFloat(image.width), proxy.size.height / CGFloat(image.height))
          let size = CGSize(
            width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
          Image(decorative: image, scale: 1).resizable().scaledToFit()
            .frame(width: size.width, height: size.height)
            .simultaneousGesture(
              LongPressGesture(minimumDuration: 0.25, maximumDistance: 20)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($comparing) { value, state, _ in
                  guard !model.cropEditing && !model.pickingNeutral else { return }
                  if case .second(true, _) = value { state = true }
                }
            )
            .onChange(of: comparing) {
              model.holdingCompare = comparing
              model.schedule()
            }
            .overlay {
              if model.cropEditing { CropOverlay(model: model) }
              if model.pickingNeutral {
                Color.clear.contentShape(.rect).onTapGesture { location in
                  model.pickNeutral([location.x / size.width, 1 - location.y / size.height])
                }.accessibilityLabel("Tap a neutral area in the photo").accessibilityAddTraits(
                  .isButton)
              }
            }
            .accessibilityLabel(
              (model.before || model.holdingCompare)
                ? "Before: RAW development only" : "Edited photo preview")
        } else {
          ContentUnavailableView(
            "Open a photo", systemImage: "camera.aperture",
            description: Text(
              "Drop a RAW, RAF, JPEG, HEIC, PNG or TIFF file here, or choose Open. Everything is developed on your device."
            )
          ).foregroundStyle(.white)
        }
        if model.showRenderInfo, model.preview != nil, !model.renderInfo.isEmpty {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(model.renderInfo, id: \.self) { Text($0) }
          }
          .font(.caption2.monospaced())
          .padding(8)
          .background(.black.opacity(0.6), in: .rect(cornerRadius: 8))
          .foregroundStyle(.white)
          .padding(8)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
          .allowsHitTesting(false)
          .accessibilityLabel("Render info")
        }
        if model.busy {
          ProgressView("Processing…").padding().background(
            .regularMaterial, in: .rect(cornerRadius: 12))
        }
        if model.pickingNeutral {
          VStack {
            Text("Tap a neutral patch").padding().background(.regularMaterial)
            Spacer()
          }
        }
        if let notice = model.notice {
          VStack {
            Spacer()
            Text(notice).font(.callout).padding(.horizontal, 14).padding(.vertical, 8)
              .background(.regularMaterial, in: .capsule).padding()
          }
          .transition(.opacity)
        }
      }
      .onChange(of: proxy.size, initial: true) { model.updateViewport(proxy.size, scale: displayScale) }
      .onChange(of: displayScale) { model.updateViewport(proxy.size, scale: displayScale) }
    }
  }
}
