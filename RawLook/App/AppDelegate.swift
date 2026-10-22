#if os(macOS)
  import AppKit

  /// Queues Finder opens received by the application delegate until an editor is ready.
  @MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
      guard let url = urls.first else { return }
      OpenRequests.shared.submit(url)
    }
  }
#endif
