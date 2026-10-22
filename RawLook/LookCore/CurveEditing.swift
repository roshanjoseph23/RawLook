import Foundation

/// A value snapshot of one tone-curve point, identified by a stable id rather than its position.
/// Views render these snapshots so a removed or inserted point can never leave a row holding a
/// stale array index.
struct CurvePointItem: Identifiable, Equatable, Sendable {
  let id: UUID
  let position: Int
  let input: Float
  let output: Float
  let isEndpoint: Bool
}

/// Index-safe tone-curve editing. Every mutation looks points up by id and validates the channel,
/// so callers never subscript the curve arrays directly.
extension EditState {
  static let maxCurvePoints = 16
  static let minCurvePointGap: Float = 0.001

  /// Keeps `curveIDs` the same shape as `curves`, minting ids for any points that lack one.
  mutating func normalizeCurveIDs() {
    if curveIDs.count > curves.count { curveIDs.removeLast(curveIDs.count - curves.count) }
    while curveIDs.count < curves.count { curveIDs.append([]) }
    for channel in curves.indices {
      let count = curves[channel].count
      if curveIDs[channel].count > count {
        curveIDs[channel].removeLast(curveIDs[channel].count - count)
      }
      while curveIDs[channel].count < count { curveIDs[channel].append(UUID()) }
    }
  }

  func hasCurve(_ channel: Int) -> Bool { curves.indices.contains(channel) }

  func curvePoints(_ channel: Int) -> [[Float]] { hasCurve(channel) ? curves[channel] : [] }

  /// Snapshots for a channel; empty when the channel does not exist.
  func curveItems(_ channel: Int) -> [CurvePointItem] {
    guard hasCurve(channel) else { return [] }
    let points = curves[channel]
    let ids = curveIDs.indices.contains(channel) ? curveIDs[channel] : []
    return points.indices.compactMap { position in
      let point = points[position]
      guard ids.indices.contains(position), point.count >= 2 else { return nil }
      return CurvePointItem(
        id: ids[position], position: position, input: point[0], output: point[1],
        isEndpoint: position == 0 || position == points.count - 1)
    }
  }

  /// The current position of a point, or nil when it no longer exists.
  func curvePosition(channel: Int, id: UUID) -> Int? {
    guard hasCurve(channel), curveIDs.indices.contains(channel),
      let position = curveIDs[channel].firstIndex(of: id),
      curves[channel].indices.contains(position), curves[channel][position].count >= 2
    else { return nil }
    return position
  }

  func canRemoveCurvePoint(channel: Int, id: UUID) -> Bool {
    guard let position = curvePosition(channel: channel, id: id) else { return false }
    return position > 0 && position < curves[channel].count - 1
  }

  /// Removes an interior point. Endpoints and unknown ids are ignored.
  @discardableResult
  mutating func removeCurvePoint(channel: Int, id: UUID) -> Bool {
    guard canRemoveCurvePoint(channel: channel, id: id),
      let position = curvePosition(channel: channel, id: id)
    else { return false }
    curves[channel].remove(at: position)
    curveIDs[channel].remove(at: position)
    return true
  }

  /// Inserts an interior point in input order, returning its id, or nil when it is not allowed
  /// (too many points, outside the endpoints, or too close to an existing point).
  mutating func insertCurvePoint(channel: Int, input: Float, output: Float) -> UUID? {
    normalizeCurveIDs()
    guard hasCurve(channel) else { return nil }
    let points = curves[channel]
    guard points.count >= 2, points.count < Self.maxCurvePoints,
      let first = points.first, let last = points.last, first.count >= 2, last.count >= 2,
      input > first[0] + 0.005, input < last[0] - 0.005,
      !points.contains(where: { $0.count >= 2 && abs($0[0] - input) < 0.005 })
    else { return nil }
    let position = points.firstIndex(where: { $0.count >= 2 && $0[0] > input }) ?? points.count - 1
    let id = UUID()
    curves[channel].insert([input, LookMath.clamp(output)], at: position)
    curveIDs[channel].insert(id, at: position)
    return id
  }

  /// Moves a point; endpoints keep their input and interior points stay between their neighbours.
  mutating func moveCurvePoint(channel: Int, id: UUID, input: Float, output: Float) {
    guard let position = curvePosition(channel: channel, id: id) else { return }
    let points = curves[channel]
    if position > 0, position < points.count - 1, points[position - 1].count >= 2,
      points[position + 1].count >= 2 {
      let low = points[position - 1][0] + Self.minCurvePointGap
      let high = points[position + 1][0] - Self.minCurvePointGap
      if low <= high { curves[channel][position][0] = min(high, max(low, input)) }
    }
    curves[channel][position][1] = LookMath.clamp(output)
  }

  /// Nudges a point's output, as the accessibility adjustable action does.
  mutating func adjustCurvePointOutput(channel: Int, id: UUID, by delta: Float) {
    guard let position = curvePosition(channel: channel, id: id) else { return }
    curves[channel][position][1] = LookMath.clamp(curves[channel][position][1] + delta)
  }

  /// The id of the point nearest to `location` (in the same units as `scale`), within `radius`.
  func nearestCurvePoint(
    channel: Int, location: (x: Double, y: Double), scale: (width: Double, height: Double),
    radius: Double
  ) -> UUID? {
    let best = curveItems(channel).map { item -> (UUID, Double) in
      let dx = Double(item.input) * scale.width - location.x
      let dy = Double(1 - item.output) * scale.height - location.y
      return (item.id, (dx * dx + dy * dy).squareRoot())
    }.min { $0.1 < $1.1 }
    guard let best, best.1 < radius else { return nil }
    return best.0
  }
}
