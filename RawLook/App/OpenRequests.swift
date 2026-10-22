import Foundation
import Observation

/// Files handed to RawLook by the macOS application delegate. The most recent request
/// waits here until a window loads it,
/// which also covers launches where the URL arrives before any view exists.
@MainActor @Observable final class OpenRequests {
  static let shared = OpenRequests()
  private(set) var pending: URL?

  func submit(_ url: URL) {
    guard url.isFileURL else { return }
    pending = url
  }

  func take() -> URL? {
    defer { pending = nil }
    return pending
  }
}
