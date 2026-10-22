import Foundation

/// File-name rules for the photos RawLook opens. Shared by drag and drop, Finder and Dock
/// opens and the RAW decoder, and kept Foundation-only so Linux can test it.
enum OpenablePhotoFile {
  /// Camera RAW extensions developed with Apple's RAW decoder.
  static let rawExtensions: Set<String> = [
    "raf", "dng", "cr2", "cr3", "nef", "nrw", "arw", "orf", "rw2", "pef", "srw", "raw", "rwl",
    "3fr", "iiq"
  ]
  /// Rendered formats decoded directly by Core Image.
  static let renderedExtensions: Set<String> = [
    "jpg", "jpeg", "jpe", "heic", "heif", "png", "tif", "tiff"
  ]

  static func isRAW(pathExtension: String) -> Bool {
    rawExtensions.contains(pathExtension.lowercased())
  }

  static func isOpenable(pathExtension: String) -> Bool {
    let suffix = pathExtension.lowercased()
    return rawExtensions.contains(suffix) || renderedExtensions.contains(suffix)
  }

  static func isOpenable(_ url: URL) -> Bool {
    url.isFileURL && isOpenable(pathExtension: url.pathExtension)
  }

  /// The single item RawLook opens from a multi-item drop or open request, plus how many
  /// other items were ignored. RawLook edits one photo at a time.
  struct Pick<Item> {
    let item: Item
    let ignoredCount: Int
  }

  /// Picks the first item `accepts` allows. Every other item, supported or not, is ignored.
  static func pick<Item>(_ items: [Item], where accepts: (Item) -> Bool) -> Pick<Item>? {
    guard let item = items.first(where: accepts) else { return nil }
    return Pick(item: item, ignoredCount: items.count - 1)
  }

  static let unsupportedMessage =
    "RawLook opens camera RAW (including Fujifilm RAF), JPEG, HEIC, PNG and TIFF files."

  static func ignoredNotice(_ count: Int) -> String? {
    guard count > 0 else { return nil }
    return count == 1
      ? "Opened the first photo. 1 other item was ignored."
      : "Opened the first photo. \(count) other items were ignored."
  }
}
