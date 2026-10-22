import SwiftUI

@main
struct RawLookApp: App {
  #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  #endif

  var body: some Scene {
    WindowGroup { ContentView() }
      .commands { CommandGroup(replacing: .undoRedo) { EditorCommands() } }
  }
}
