import SwiftUI

/// Shown over the editor while a drag hovers it.
struct PhotoDropHighlight: View {
  var body: some View {
    RoundedRectangle(cornerRadius: 14)
      .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
      .background(.tint.opacity(0.12), in: .rect(cornerRadius: 14))
      .overlay {
        Label("Drop to open", systemImage: "square.and.arrow.down")
          .font(.headline)
          .padding(.horizontal, 16).padding(.vertical, 10)
          .background(.regularMaterial, in: .capsule)
      }
      .padding(8)
      .allowsHitTesting(false)
      .accessibilityElement(children: .combine)
  }
}
