import Foundation

struct EditState: Codable, Sendable, Equatable {
  var exposure: Float = 0
  var temperature: Float = 6500
  var tint: Float = 0
  var whiteBalanceMode: WhiteBalanceMode = .asShot
  var neutralGains: [Float]?
  var presetID: String?
  var strength: Float = 1
  var curves: [[[Float]]] = []
  var curveIDs: [[UUID]] = []
  var adjustments: [Adjustment: Float] = [:]
  var crop = CropGeometry.Rect()
  var cropAspect: CropAspect = .free
  var cropPortrait = false
  var straighten: Double = 0
  var quarterTurns = 0
  var flipHorizontal = false
  var flipVertical = false
}
