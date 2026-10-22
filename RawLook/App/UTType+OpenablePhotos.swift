import UniformTypeIdentifiers

extension UTType {
  /// Apple's system identifier for Fujifilm RAF files.
  static let fujifilmRAW = UTType("com.fuji.raw-image") ?? UTType(importedAs: "com.fuji.raw-image", conformingTo: .rawImage)

  /// Everything the in-app open panel accepts. `.image` already covers RAW types; the
  /// explicit entries keep RAF selectable even where the system type is unavailable.
  static let openablePhotoTypes: [UTType] = [.image, .rawImage, .fujifilmRAW, .jpeg, .heic, .png, .tiff]
}
