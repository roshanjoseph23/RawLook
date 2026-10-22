import Foundation
import Observation

/// Files handed to RawLook by the macOS application delegate (Finder Open With, double-click
/// and drops onto the Dock icon). The most recent request waits here until a window loads it,
/// which also covers launches where the URL arrives before any view exists.
@MainActor @Observable final class OpenRequests {
  struct Request: Equatable {
    let url: URL
    /// Other files in the same open request that RawLook ignored.
    let ignoredCount: Int
  }

  static let shared = OpenRequests()
  private(set) var pending: Request?

  func submit(_ url: URL, ignoredCount: Int = 0) {
    guard url.isFileURL else { return }
    pending = Request(url: url, ignoredCount: ignoredCount)
  }

  func take() -> Request? {
    defer { pending = nil }
    return pending
  }
}
