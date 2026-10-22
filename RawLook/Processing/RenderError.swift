import Foundation

enum RenderError: Error, LocalizedError {
  case message(String)
  var errorDescription: String? {
    switch self {
    case .message(let text): text
    }
  }
}
