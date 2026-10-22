#if canImport(UniformTypeIdentifiers)
  import UniformTypeIdentifiers
#endif
enum ExportFormat: String, Codable, Sendable, CaseIterable {
  case jpeg, tiff16, heic
  var fileExtension: String {
    switch self {
    case .jpeg: "jpg"
    case .tiff16: "tiff"
    case .heic: "heic"
    }
  }
  var displayName: String {
    switch self {
    case .jpeg: "JPEG"
    case .tiff16: "16-bit TIFF"
    case .heic: "HEIC"
    }
  }
  #if canImport(UniformTypeIdentifiers)
    var contentType: UTType {
      switch self {
      case .jpeg: .jpeg
      case .tiff16: .tiff
      case .heic: .heic
      }
    }
  #endif
}
