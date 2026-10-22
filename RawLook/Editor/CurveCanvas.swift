import SwiftUI

/// A decorative distribution behind the editable tone curve; point rows provide accessible editing.
struct CurveCanvas: View {
  let points: [[Float]]
  let histogram: [Float]
  var body: some View {
    Canvas { context, size in
      var distribution = Path()
      let peak = histogram.max() ?? 0
      if peak > 0 {
        distribution.move(to: CGPoint(x: 0, y: size.height))
        for (bin, count) in histogram.enumerated() {
          distribution.addLine(
            to: CGPoint(
              x: Double(bin) / 255 * size.width, y: size.height * (1 - Double(count / peak))))
        }
        distribution.addLine(to: CGPoint(x: size.width, y: size.height))
        distribution.closeSubpath()
        context.fill(distribution, with: .color(.secondary.opacity(0.12)))
      }
      var grid = Path()
      for step in 0...4 {
        let t = CGFloat(step) / 4
        grid.move(to: CGPoint(x: t * size.width, y: 0))
        grid.addLine(to: CGPoint(x: t * size.width, y: size.height))
        grid.move(to: CGPoint(x: 0, y: t * size.height))
        grid.addLine(to: CGPoint(x: size.width, y: t * size.height))
      }
      context.stroke(grid, with: .color(.secondary.opacity(0.25)))
      var line = Path()
      for (i, p) in points.enumerated() {
        let point = CGPoint(x: CGFloat(p[0]) * size.width, y: CGFloat(1 - p[1]) * size.height)
        if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
        context.fill(
          Path(ellipseIn: CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)),
          with: .color(.accentColor))
      }
      context.stroke(line, with: .color(.primary), lineWidth: 2)
    }
  }
}
