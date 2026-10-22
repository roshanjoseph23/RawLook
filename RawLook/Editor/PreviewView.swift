import SwiftUI

struct PreviewView: View {
  @Bindable var model: EditorModel
  @GestureState private var comparing = false
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
            description: Text("Develop RAW, RAF, JPEG, HEIC, PNG or TIFF entirely on your device.")
          ).foregroundStyle(.white)
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
      }
    }
  }
}
