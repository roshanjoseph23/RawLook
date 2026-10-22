import Foundation
import UniformTypeIdentifiers

/// A dropped photo ready for the same URL loading path as the open panel.
struct DroppedPhoto: Sendable {
  let url: URL
  /// The private folder holding RawLook's own copy, removed once the photo is loaded.
  /// Nil when the drop handed over the original file URL (Finder drags on macOS).
  let temporaryDirectory: URL?

  func removeTemporaryCopy() {
    guard let temporaryDirectory else { return }
    try? FileManager.default.removeItem(at: temporaryDirectory)
  }
}

enum PhotoDropError: LocalizedError {
  case unsupported

  var errorDescription: String? { OpenablePhotoFile.unsupportedMessage }
}

/// Turns drag-and-drop item providers into a photo file RawLook can load.
///
/// macOS Finder drags provide file URLs, and the drag grants the sandbox read access. Files
/// and Photos on iPad provide file representations instead; those are copied byte for byte
/// into a private temporary folder, so RAW data stays RAW and is never converted to JPEG.
enum PhotoDrop {
  /// Loads the first provider that yields a supported photo. RawLook edits one photo at a
  /// time, so every other dropped item is ignored and counted.
  @MainActor static func receive(_ providers: [NSItemProvider]) async throws -> (
    photo: DroppedPhoto, ignoredCount: Int
  ) {
    var lastError: Error = PhotoDropError.unsupported
    for provider in providers {
      do {
        let photo = try await receive(provider)
        return (photo, providers.count - 1)
      } catch {
        lastError = error
      }
    }
    throw lastError
  }

  @MainActor private static func receive(_ provider: NSItemProvider) async throws -> DroppedPhoto {
    let photoType = UTType.preferredPhotoType(in: provider.registeredContentTypes)
    let hasFileURL = provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
    #if os(macOS)
      // Finder: open the original file in place.
      if hasFileURL, let photo = try? await originalFile(from: provider) {
        // A sender can offer a JPEG file URL alongside its original RAW representation.
        // Keep Finder's in-place path, but never let that preview override advertised RAW.
        if let photoType, photoType.isRAWPhoto,
          !OpenablePhotoFile.isRAW(pathExtension: photo.url.pathExtension),
          UTType(filenameExtension: photo.url.pathExtension)?.isRAWPhoto != true
        {
          return try await copiedFile(from: provider, type: photoType)
        }
        return photo
      }
      if let photoType { return try await copiedFile(from: provider, type: photoType) }
    #else
      // Files and Photos: another app's file URL is not readable here, so copy the data.
      if let photoType { return try await copiedFile(from: provider, type: photoType) }
      if hasFileURL { return try await originalFile(from: provider) }
    #endif
    throw PhotoDropError.unsupported
  }

  @MainActor private static func originalFile(from provider: NSItemProvider) async throws
    -> DroppedPhoto
  {
    let url: URL = try await withCheckedThrowingContinuation { continuation in
      _ = provider.loadObject(ofClass: URL.self) { @Sendable url, error in
        if let url {
          continuation.resume(returning: url)
        } else {
          continuation.resume(throwing: error ?? PhotoDropError.unsupported)
        }
      }
    }
    guard UTType.isOpenablePhotoFile(url) else { throw PhotoDropError.unsupported }
    return DroppedPhoto(url: url, temporaryDirectory: nil)
  }

  @MainActor private static func copiedFile(from provider: NSItemProvider, type: UTType)
    async throws -> DroppedPhoto
  {
    let suggestedName = provider.suggestedName
    return try await withCheckedThrowingContinuation { continuation in
      // The provided file is deleted when this handler returns, so copy it synchronously.
      _ = provider.loadFileRepresentation(for: type, openInPlace: false) { @Sendable url, _, error in
        guard let url else {
          continuation.resume(throwing: error ?? PhotoDropError.unsupported)
          return
        }
        continuation.resume(
          with: Result { try copyToTemporaryFolder(url, type: type, suggestedName: suggestedName) })
      }
    }
  }

  private static func copyToTemporaryFolder(_ source: URL, type: UTType, suggestedName: String?)
    throws -> DroppedPhoto
  {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory
      .appendingPathComponent("RawLookDrops", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    do {
      let name = fileName(source: source, type: type, suggestedName: suggestedName)
      let destination = directory.appendingPathComponent(name, isDirectory: false)
      try manager.copyItem(at: source, to: destination)
      return DroppedPhoto(url: destination, temporaryDirectory: directory)
    } catch {
      try? manager.removeItem(at: directory)
      throw error
    }
  }

  /// A readable file name whose extension matches the loaded content type, so the loader
  /// sees RAF as RAF even when the sender's temporary file has a generic name.
  static func fileName(source: URL, type: UTType, suggestedName: String?) -> String {
    let suggested = suggestedName.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
    let candidates = [suggested, source.lastPathComponent].filter { !$0.isEmpty }
    let base =
      candidates.lazy.map { ($0 as NSString).deletingPathExtension }.first { !$0.isEmpty }
      ?? "Photo"
    let matchingExtension = candidates.lazy.map { ($0 as NSString).pathExtension }.first { suffix in
      !suffix.isEmpty && UTType(filenameExtension: suffix)?.conforms(to: type) == true
    }
    let suffix =
      matchingExtension ?? type.preferredFilenameExtension
      ?? (source.pathExtension.isEmpty ? nil : source.pathExtension)
    let safeBase = base.replacingOccurrences(of: ":", with: "-")
    return suffix.map { "\(safeBase).\($0)" } ?? safeBase
  }
}
