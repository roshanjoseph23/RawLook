import Foundation

enum PresetError: Error, LocalizedError {
  case schema, version, order, anchors, curve, nonfinite
  var errorDescription: String? {
    switch self {
    case .schema: "Expected reference-photo-look schema."
    case .version: "Only schema major version 1 is supported."
    case .order: "Unsupported or out-of-order pipeline stage."
    case .anchors: "Use 1–16 finite, sorted, unique hue anchors in [0, 360)."
    case .curve: "Curves need 2–16 finite [x,y] knots with increasing x in [0,1]."
    case .nonfinite: "Invalid preset numeric value or strength."
    }
  }
}
