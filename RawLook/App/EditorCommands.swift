import SwiftUI

struct EditorCommands: View {
  @FocusedValue(\.editor) private var model
  var body: some View {
    Button("Undo") { model?.undo() }.keyboardShortcut("z").disabled(model?.canUndo != true)
    Button("Redo") { model?.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(
      model?.canRedo != true)
  }
}
