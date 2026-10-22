import Foundation

struct PresetLibrary: Sendable, Equatable {
  var presets: [Preset] = []
  /// Real problems only (invalid JSON, unsupported effects, conflicting duplicates).
  var warnings: [String] = []

  static func load(bundle: Bundle = .main) -> Self {
    #if os(Linux)
      // swift-corelibs-foundation returns NSURL here; the recursive scan below covers it.
      var urls = Set<URL>()
    #else
      var urls = Set(bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
    #endif
    if let root = bundle.resourceURL,
      let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
      for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
        urls.insert(url)
      }
    }
    return load(urls: Array(urls))
  }

  /// Decode every URL, then resolve duplicates:
  /// - a preset listing another preset's id in `supersedes` replaces it silently;
  /// - presets sharing an id keep the highest `preset_version` silently (for example a stale
  ///   copy of an older version left in a build folder). Only equal versions of one id warn.
  static func load(urls: [URL]) -> Self {
    var result = Self()
    var decoded: [Preset] = []
    for url in urls.sorted(by: { $0.path < $1.path }) {
      do {
        let preset = try Preset.decode(Data(contentsOf: url))
        result.warnings += try preset.validate().map { "\(preset.name): \($0)" }
        decoded.append(preset)
      } catch { result.warnings.append("\(url.lastPathComponent): \(error.localizedDescription)") }
    }
    var byID: [String: Preset] = [:]
    var order: [String] = []
    var versionsByID: [String: [Preset]] = [:]
    for preset in decoded {
      let previousVersions = versionsByID[preset.id, default: []]
      if previousVersions.contains(where: {
        Preset.compareVersions($0.presetVersion, preset.presetVersion) == .orderedSame
          && $0 != preset
      }) {
        result.warnings.append("Duplicate preset ID with the same version: \(preset.id)")
      }
      versionsByID[preset.id, default: []].append(preset)
      guard let existing = byID[preset.id] else {
        byID[preset.id] = preset
        order.append(preset.id)
        continue
      }
      switch Preset.compareVersions(preset.presetVersion, existing.presetVersion) {
      case .orderedDescending: byID[preset.id] = preset
      case .orderedAscending: break
      case .orderedSame: break
      }
    }
    // Only the selected version may retire other presets. Stale versions must not hide them.
    let superseded = Set(byID.values.flatMap { $0.supersedes ?? [] })
    result.presets = order.filter { !superseded.contains($0) }.compactMap { byID[$0] }
    return result
  }
}

extension Preset {
  /// Compare dotted numeric versions; a missing version counts as 0.
  static func compareVersions(_ a: String?, _ b: String?) -> ComparisonResult {
    func parts(_ v: String?) -> [Int] {
      (v ?? "0").split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
    let x = parts(a)
    let y = parts(b)
    for i in 0..<max(x.count, y.count) {
      let l = i < x.count ? x[i] : 0
      let r = i < y.count ? y[i] : 0
      if l != r { return l < r ? .orderedAscending : .orderedDescending }
    }
    return .orderedSame
  }
}
