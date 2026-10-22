import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
final class EditorModel {
  var state = EditState()
  var library = PresetLibrary()
  var preview: CGImage?
  var error: String?
  var busy = false
  var loaded = false
  var isRAW = false
  var before = false
  var dragging = false
  var cropEditing = false
  var pickingNeutral = false
  var sourceAspect: Double = 1
  var imageAspect: Double { state.quarterTurns.isMultiple(of: 2) ? sourceAspect : 1 / sourceAspect }
  var photo: PhotosPickerItem?
  var format: ExportFormat = .jpeg
  var quality = 0.92
  var colorProfile: ColorProfile = .sRGB
  var holdingCompare = false
  var histogram: [Float] = []
  var exportDocument: ExportDocument?
  var showExporter = false
  var sourceName = "Photo"
  private var asShot: (Float, Float) = (6500, 0)
  private var undoStack: [EditState] = []
  private var redoStack: [EditState] = []
  private var transaction: EditState?
  private var observedState = EditState()
  private var renderTask: Task<Void, Never>?
  private var generation = 0
  private let renderer = PhotoRenderer()
  var preset: Preset? { library.presets.first { $0.id == state.presetID } }
  var canUndo: Bool { !undoStack.isEmpty }
  var canRedo: Bool { !redoStack.isEmpty }
  var exportType: UTType { format.contentType }
  var exportName: String { sourceName + "-RawLook." + format.fileExtension }
  var cropAspectSelection: CropAspect {
    get { state.cropAspect }
    set {
      state.cropAspect = newValue
      fitCrop()
    }
  }
  var cropPortraitSelection: Bool {
    get { state.cropPortrait }
    set {
      state.cropPortrait = newValue
      fitCrop()
    }
  }
  /// Only user selection changes refit the crop; undo restores the saved rectangle exactly.
  func fitCrop() {
    guard let ratio = state.cropAspect.ratio(imageAspect: imageAspect, portrait: state.cropPortrait)
    else { return }
    state.crop = CropGeometry.fit(aspect: ratio, imageAspect: imageAspect)
  }
  var selectedPresetID: String? {
    get { state.presetID }
    set {
      state.presetID = newValue
      choosePreset()
    }
  }
  var whiteBalanceSelection: WhiteBalanceMode {
    get { state.whiteBalanceMode }
    set { if newValue == .asShot { resetWB() } else { manualWB() } }
  }
  func startNeutralPicking() {
    cropEditing = false
    pickingNeutral = true
    before = true
  }
  var temperature: Float {
    get { state.temperature }
    set {
      manualWB()
      state.temperature = newValue
    }
  }
  var tint: Float {
    get { state.tint }
    set {
      manualWB()
      state.tint = newValue
    }
  }
  subscript(adjustment key: Adjustment) -> Float {
    get { state.adjustments[key] ?? 0 }
    set { state.adjustments[key] = newValue }
  }
  func start() { library = .load() }
  func begin() {
    if transaction == nil { transaction = observedState }
    dragging = true
  }
  func end() {
    if let old = transaction, old != state {
      undoStack.append(old)
      redoStack = []
    }
    transaction = nil
    dragging = false
    observedState = state
    schedule()
  }
  func changed() {
    if transaction == nil && state != observedState {
      undoStack.append(observedState)
      redoStack = []
    }
    observedState = state
    schedule()
  }
  func undo() {
    guard let old = undoStack.popLast() else { return }
    redoStack.append(state)
    state = old
    observedState = old
    schedule()
  }
  func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(state)
    state = next
    observedState = next
    schedule()
  }
  func choosePreset() {
    guard let p = preset?.estimatedCreativePipeline else {
      state.curves = []
      state.curveIDs = []
      return
    }
    state.strength = p.strengthBlendLinearSrgb.defaultStrength
    state.curves = [
      p.masterRgbToneCurve.points, p.perChannelToneCurves.red, p.perChannelToneCurves.green,
      p.perChannelToneCurves.blue
    ]
    state.curveIDs = state.curves.map { $0.map { _ in UUID() } }
  }
  func resetCurve(_ channel: Int?) {
    guard let p = preset?.estimatedCreativePipeline else { return }
    let curves = [
      p.masterRgbToneCurve.points, p.perChannelToneCurves.red, p.perChannelToneCurves.green,
      p.perChannelToneCurves.blue
    ]
    if let channel {
      state.curves[channel] = curves[channel]
      state.curveIDs[channel] = curves[channel].map { _ in UUID() }
    } else {
      state.curves = curves
      state.curveIDs = curves.map { $0.map { _ in UUID() } }
    }
  }
  func removeCurvePoint(channel: Int, index: Int) {
    state.curves[channel].remove(at: index)
    state.curveIDs[channel].remove(at: index)
  }
  var showingError: Bool {
    get { error != nil }
    set { if !newValue { error = nil } }
  }
  func resetWB() {
    state.temperature = asShot.0
    state.tint = asShot.1
    state.whiteBalanceMode = .asShot
    state.neutralGains = nil
  }
  func manualWB() {
    state.whiteBalanceMode = .manual
    state.neutralGains = nil
  }
  func resetGeometry() {
    state.crop = .init()
    state.cropAspect = .free
    state.cropPortrait = false
    state.straighten = 0
    state.quarterTurns = 0
    state.flipHorizontal = false
    state.flipVertical = false
  }
  func schedule() {
    renderTask?.cancel()
    generation += 1
    guard loaded else { return }
    let ticket = generation
    let snapshot = state
    let selected = preset
    let compare = before || holdingCompare
    let crop = cropEditing
    let neutral = pickingNeutral
    renderTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(dragging ? 50 : 15))
        let image = try await renderer.preview(
          state: snapshot, preset: selected, size: dragging ? 800 : 1800, before: compare,
          cropEditing: crop, neutralEditing: neutral)
        guard !Task.isCancelled, ticket == generation else { return }
        let bins = await renderer.histogram(image)
        guard !Task.isCancelled, ticket == generation else { return }
        preview = image
        histogram = bins
      } catch is CancellationError {} catch {
        if ticket == generation { self.error = error.localizedDescription }
      }
    }
  }
  func openURL(_ result: Result<[URL], Error>) {
    Task {
      do {
        guard let url = try result.get().first else { return }
        busy = true
        defer { busy = false }
        renderTask?.cancel()
        generation += 1
        let info = try await renderer.load(url: url)
        finishLoad(info: info, name: url.deletingPathExtension().lastPathComponent)

      } catch { self.error = error.localizedDescription }
    }
  }
  func openPhoto() {
    guard let photo else { return }
    Task {
      busy = true
      defer { busy = false }
      do {
        guard let data = try await photo.loadTransferable(type: Data.self) else {
          throw RenderError.message("Photos did not provide image data.")
        }
        let type =
          photo.supportedContentTypes.first { $0.conforms(to: .rawImage) }
          ?? photo.supportedContentTypes.first
        try await load(
          data: data, hint: type?.identifier, raw: type?.conforms(to: .rawImage) == true,
          name: "Photo")
      } catch { self.error = error.localizedDescription }
    }
  }
  private func load(data: Data, hint: String?, raw: Bool, name: String) async throws {
    busy = true
    defer { busy = false }
    renderTask?.cancel()
    generation += 1
    let info = try await renderer.load(data: data, hint: hint, requireRAW: raw)
    finishLoad(info: info, name: name)
  }
  private func finishLoad(info: PhotoInfo, name: String) {
    state = EditState()
    asShot = (info.temperature, info.tint)
    isRAW = info.isRAW
    sourceAspect = info.width / info.height
    state.temperature = info.temperature
    state.tint = info.tint
    state.presetID = library.presets.first?.id
    choosePreset()
    observedState = state
    undoStack = []
    redoStack = []
    transaction = nil
    sourceName = name
    loaded = true
    cropEditing = false
    pickingNeutral = false
    before = false
    holdingCompare = false
    schedule()
  }

  func pickNeutral(_ point: [Double]) {
    pickingNeutral = false
    Task {
      do {
        if isRAW {
          let balance = try await renderer.neutralWhiteBalance(state: state, point: point)
          state.whiteBalanceMode = .manual
          state.temperature = balance.0
          state.tint = balance.1
          state.neutralGains = nil
        } else {
          state.neutralGains = try await renderer.neutralGains(state: state, point: point)
        }
        before = false
        changed()
      } catch { self.error = error.localizedDescription }
    }
  }
  func export(photos: Bool = false) {
    let snapshot = state
    let selected = preset
    let format = format
    let quality = quality
    let profile = colorProfile
    Task {
      busy = true
      defer { busy = false }
      do {
        let data = try await renderer.export(
          state: snapshot, preset: selected, format: format, quality: quality, profile: profile)
        if photos {
          let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
          guard status == .authorized || status == .limited else {
            throw RenderError.message("Allow adding photos in Settings to save this export.")
          }
          try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
          }
        } else {
          exportDocument = ExportDocument(data: data)
          showExporter = true
        }
      } catch { self.error = error.localizedDescription }
    }
  }
}
