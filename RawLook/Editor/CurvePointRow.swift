import SwiftUI

/// One tone-curve point. It renders a value snapshot and acts through closures keyed by the
/// point's id, so it never reads the curve arrays by a possibly stale index.
struct CurvePointRow: View {
  let item: CurvePointItem
  let onAdjust: (Float) -> Void
  let onRemove: () -> Void
  var body: some View {
    HStack {
      Text("Point \(item.position + 1)")
      Spacer()
      Text(item.output, format: .number.precision(.fractionLength(2)))
      if !item.isEndpoint {
        Button("Remove point \(item.position + 1)", systemImage: "minus.circle", action: onRemove)
          .labelStyle(.iconOnly)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAdjustableAction { direction in
      onAdjust(direction == .increment ? 0.01 : -0.01)
    }
  }
}
