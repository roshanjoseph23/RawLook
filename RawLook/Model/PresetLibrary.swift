import Foundation

struct PresetLibrary: Sendable, Equatable {
  var presets: [Preset] = []
  var warnings: [String] = []
  static func load(bundle: Bundle = .main) -> Self {
    var result = Self()
    var urls = Set(bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
    if let root = bundle.resourceURL,
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
      for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
        urls.insert(url)
      }
    }
    for url in urls.sorted(by: { $0.path < $1.path }) {
      do {
        let preset = try Preset.decode(Data(contentsOf: url))
        result.warnings += try preset.validate().map { "\(preset.name): \($0)" }
        if result.presets.contains(where: { $0.id == preset.id }) {
          result.warnings.append("Duplicate preset ID: \(preset.id)")
          continue
        }
        result.presets.append(preset)
      } catch { result.warnings.append("\(url.lastPathComponent): \(error.localizedDescription)") }
    }
    return result
  }
}
