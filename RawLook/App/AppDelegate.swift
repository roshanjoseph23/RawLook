#if os(macOS)
  import AppKit
  import UniformTypeIdentifiers

  /// Queues Finder opens and Dock icon drops until an editor is ready. The Dock only accepts
  /// files matching the document types declared in Info.plist, and AppKit delivers those
  /// drops here, the same as Open With.
  @MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
      // Open the first supported photo. If none qualifies, pass the first file on so the
      // loader reports why it cannot be opened.
      let pick = OpenablePhotoFile.pick(urls, where: UTType.isOpenablePhotoFile)
      guard let url = pick?.item ?? urls.first else { return }
      OpenRequests.shared.submit(url, ignoredCount: urls.count - 1)
    }
  }
#endif
