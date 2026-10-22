import Foundation
import UniformTypeIdentifiers

extension UTType {
  /// Apple's system identifier for Fujifilm RAF files.
  static let fujifilmRAW = UTType("com.fuji.raw-image") ?? UTType(importedAs: "com.fuji.raw-image", conformingTo: .rawImage)

  /// Everything the in-app open panel accepts. `.image` already covers RAW types; the
  /// explicit entries keep RAF selectable even where the system type is unavailable.
  static let openablePhotoTypes: [UTType] = [.image, .rawImage, .fujifilmRAW, .jpeg, .heic, .png, .tiff]

  /// Rendered formats RawLook decodes directly, in drop preference order.
  static let renderedPhotoTypes: [UTType] = [.jpeg, .heic, .heif, .png, .tiff]

  /// Content types the drop target advertises. File URLs cover Finder drags on macOS; the
  /// photo types cover file representations from Files and Photos on iPad and iPhone.
  static let droppablePhotoTypes: [UTType] = [.fileURL, .rawImage, .fujifilmRAW] + renderedPhotoTypes

  var isRAWPhoto: Bool { conforms(to: .rawImage) || conforms(to: .fujifilmRAW) }

  /// True for camera RAW and the rendered formats RawLook supports. Generic `.image` and
  /// other image formats (GIF, BMP, PDF and so on) are rejected.
  var isOpenablePhoto: Bool {
    isRAWPhoto || Self.renderedPhotoTypes.contains { conforms(to: $0) }
  }

  /// Chooses which representation to load from an item that offers several. RAW wins over
  /// rendered previews so a RAW+JPEG item keeps its RAW data. Returns nil when nothing fits.
  static func preferredPhotoType(in types: [UTType]) -> UTType? {
    types.first(where: \.isRAWPhoto)
      ?? renderedPhotoTypes.lazy.compactMap { rendered in types.first { $0.conforms(to: rendered) } }
      .first
  }

  /// Whether a file URL names a photo RawLook can open, by its content type or extension.
  static func isOpenablePhotoFile(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    if let type = UTType(filenameExtension: url.pathExtension), type.isOpenablePhoto { return true }
    return OpenablePhotoFile.isOpenable(url)
  }
}
