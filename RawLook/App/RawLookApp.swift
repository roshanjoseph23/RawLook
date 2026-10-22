import SwiftUI

@main
struct RawLookApp: App {
  var body: some Scene {
    WindowGroup { ContentView() }
      .commands { CommandGroup(replacing: .undoRedo) { EditorCommands() } }
  }
}
