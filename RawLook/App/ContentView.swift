import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @State private var model = EditorModel()
  @State private var importing = false
  @State private var tools = false
  var body: some View {
    @Bindable var model = model
    GeometryReader { geometry in
      NavigationStack {
        HStack(spacing: 0) {
          PreviewView(model: model)
          if geometry.size.width >= 760 { EditorInspector(model: model).frame(width: 320) }
        }
        .navigationTitle("RawLook")
        .toolbar {
          ToolbarItemGroup {
            Button("Open", systemImage: "folder") { importing = true }
            #if os(iOS)
              PhotosPicker(
                selection: $model.photo, matching: .images, preferredItemEncoding: .current,
                photoLibrary: .shared()
              ) { Label("Photos", systemImage: "photo.on.rectangle") }
            #endif
            Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo).disabled(
              !model.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo).disabled(
              !model.canRedo)
            Toggle(isOn: $model.before) { Label("Before", systemImage: "circle.lefthalf.filled") }
              .disabled(!model.loaded)
            if geometry.size.width < 760 {
              Button("Tools", systemImage: "slider.horizontal.3") { tools = true }
            }
          }
        }
        .safeAreaInset(edge: .bottom) {
          if geometry.size.width < 760 {
            Button("Edit photo", systemImage: "slider.horizontal.3") { tools = true }.padding()
              .frame(maxWidth: .infinity).background(.bar)
          }
        }
      }
    }
    .focusedSceneValue(\.editor, model)
    .task { model.start() }
    .onChange(of: model.state) { model.changed() }
    .onChange(of: model.before) { model.schedule() }
    .onChange(of: model.cropEditing) {
      if model.cropEditing { tools = false }
      model.schedule()
    }
    .onChange(of: model.pickingNeutral) {
      if model.pickingNeutral { tools = false }
      model.schedule()
    }
    .onChange(of: model.photo) { model.openPhoto() }
    .sheet(isPresented: $tools) {
      NavigationStack {
        EditorInspector(model: model).toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { tools = false } }
        }
      }.presentationDetents([.medium, .large])
    }
    .fileImporter(
      isPresented: $importing,
      allowedContentTypes: [.image, .rawImage, UTType("com.fuji.raw-image") ?? .rawImage],
      allowsMultipleSelection: false, onCompletion: model.openURL
    )
    .fileExporter(
      isPresented: $model.showExporter, document: model.exportDocument,
      contentType: model.exportType, defaultFilename: model.exportName
    ) { result in
      if case .failure(let error) = result { model.error = error.localizedDescription }
    }
    .alert("RawLook", isPresented: $model.showingError) {
      Button("OK") { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
  }
}
