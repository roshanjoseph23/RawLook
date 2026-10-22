import Foundation
import XCTest

#if os(Linux)
  @testable import RawLookCore
#else
  @testable import RawLook
#endif

final class PresetLibraryTests: XCTestCase {
  #if os(Linux)
    private var repo: URL {
      URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent()
    }
    /// Mirrors project.yml: the app ships every JSON directly in Presets/ (not Presets/source).
    private func appPresetURLs() throws -> [URL] {
      try FileManager.default.contentsOfDirectory(
        at: repo.appendingPathComponent("Presets"), includingPropertiesForKeys: nil
      ).filter { $0.pathExtension == "json" }
    }
    private var originalURL: URL {
      get throws {
        repo.appendingPathComponent("Presets/source/warm-garden-portraits.json")
      }
    }
  #else
    private func appPresetURLs() throws -> [URL] {
      var urls = Set(Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
      if let root = Bundle.main.resourceURL,
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
          urls.insert(url)
        }
      }
      return Array(urls)
    }
    private var originalURL: URL {
      get throws {
        try XCTUnwrap(
          Bundle(for: Self.self).url(forResource: "warm-garden-portraits", withExtension: "json"))
      }
    }
  #endif

  private func tunedURL() throws -> URL {
    try XCTUnwrap(try appPresetURLs().first { $0.lastPathComponent == "warm-garden-portraits.json" })
  }

  private func write(_ preset: Preset, _ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "preset-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    addTeardownBlock { try FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent(name)
    try preset.encoded().write(to: url)
    return url
  }

  func testBundledAppPresetsHaveUniqueIDsAndNoWarnings() throws {
    let urls = try appPresetURLs()
    XCTAssertFalse(urls.isEmpty)
    let decoded = try urls.map { try Preset.decode(Data(contentsOf: $0)) }
    XCTAssertEqual(Set(decoded.map(\.id)).count, decoded.count, "bundled preset ids must be unique")
    #if os(Linux)
      let library = PresetLibrary.load(urls: urls)
    #else
      let library = PresetLibrary.load(bundle: .main)
    #endif
    XCTAssertEqual(library.warnings, [])
    XCTAssertEqual(Set(library.presets.map(\.id)).count, library.presets.count)
    let tuned = try XCTUnwrap(library.presets.first { $0.id == "warm-garden-portraits" })
    XCTAssertEqual(tuned.presetVersion, "1.3.0")
  }

  func testTunedPresetSupersedesOriginalWithoutWarning() throws {
    let original = try Preset.decode(Data(contentsOf: try originalURL))
    let tuned = try Preset.decode(Data(contentsOf: try tunedURL()))
    XCTAssertNil(original.supersedes)
    XCTAssertEqual(try Preset.decode(tuned.encoded()), tuned)
    XCTAssertNotEqual(tuned.id, original.id)
    XCTAssertEqual(tuned.supersedes, [original.id, "warm-garden-portraits-v1-2"])
    // A stale copy of the original next to the tuned preset (old build folder) is hidden.
    let library = PresetLibrary.load(urls: [try originalURL, try tunedURL()])
    XCTAssertEqual(library.presets.map(\.id), [tuned.id])
    XCTAssertEqual(library.warnings, [])
  }

  func testSameIDPrefersHigherVersionSilently() throws {
    var newer = try Preset.decode(Data(contentsOf: try tunedURL()))
    newer.supersedes = nil
    var older = newer
    older.presetVersion = "1.1.0"
    older.estimatedCreativePipeline.globalHslSaturation.multiplier = 0.9
    var unversioned = newer
    unversioned.presetVersion = nil
    let urls = [try write(newer, "b.json"), try write(older, "a.json"), try write(unversioned, "c.json")]
    let library = PresetLibrary.load(urls: urls)
    XCTAssertEqual(library.presets, [newer])
    XCTAssertEqual(library.warnings, [])
  }

  func testSameIDAndVersionWithDifferentContentWarns() throws {
    let a = try Preset.decode(Data(contentsOf: try tunedURL()))
    var b = a
    b.estimatedCreativePipeline.globalHslSaturation.multiplier = 0.5
    let library = PresetLibrary.load(urls: [try write(a, "a.json"), try write(b, "b.json")])
    XCTAssertEqual(library.presets.count, 1)
    XCTAssertEqual(library.warnings.count, 1)
    // Identical copies (the same file bundled twice) are not a problem.
    let twins = PresetLibrary.load(urls: [try write(a, "a.json"), try write(a, "b.json")])
    XCTAssertEqual(twins.presets.count, 1)
    XCTAssertEqual(twins.warnings, [])
  }

  func testDiscardedVersionDoesNotSupersedeAnotherPreset() throws {
    let original = try Preset.decode(Data(contentsOf: try originalURL))
    var newer = try Preset.decode(Data(contentsOf: try tunedURL()))
    var older = newer
    older.presetVersion = "1.1.0"
    newer.supersedes = nil
    let library = PresetLibrary.load(urls: [
      try originalURL, try write(older, "older.json"), try write(newer, "newer.json")
    ])
    XCTAssertEqual(Set(library.presets.map(\.id)), [original.id, newer.id])
    XCTAssertEqual(library.warnings, [])
  }

  func testConflictingOlderVersionsWarnRegardlessOfLoadOrder() throws {
    let newer = try Preset.decode(Data(contentsOf: try tunedURL()))
    var older = newer
    older.presetVersion = "1.1.0"
    var conflict = older
    conflict.name += " changed"
    // Use a single directory so filename sorting controls the load order.
    let first = try write(newer, "a.json")
    let second = first.deletingLastPathComponent().appendingPathComponent("b.json")
    let third = first.deletingLastPathComponent().appendingPathComponent("c.json")
    try older.encoded().write(to: second)
    try conflict.encoded().write(to: third)
    for earliest in [newer, older] {
      try earliest.encoded().write(to: first)
      try (earliest == newer ? older : newer).encoded().write(to: second)
      let library = PresetLibrary.load(urls: [first, second, third])
      XCTAssertEqual(library.presets, [newer])
      XCTAssertEqual(library.warnings.count, 1)
    }
  }

  func testVersionComparison() {
    XCTAssertEqual(Preset.compareVersions("1.2.0", "1.1.9"), .orderedDescending)
    XCTAssertEqual(Preset.compareVersions("1.10", "1.9"), .orderedDescending)
    XCTAssertEqual(Preset.compareVersions("1.2", "1.2.0"), .orderedSame)
    XCTAssertEqual(Preset.compareVersions(nil, "0.0.1"), .orderedAscending)
    XCTAssertEqual(Preset.compareVersions(nil, nil), .orderedSame)
  }
}
