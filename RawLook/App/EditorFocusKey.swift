import SwiftUI

struct EditorFocusKey: FocusedValueKey { typealias Value = EditorModel }

extension FocusedValues {
  var editor: EditorModel? {
    get { self[EditorFocusKey.self] }
    set { self[EditorFocusKey.self] = newValue }
  }
}
