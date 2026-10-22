import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

extension PhotoRenderer {
  func export(
    state: EditState, preset: Preset?, format: ExportFormat, quality: Double, profile: ColorProfile
  ) throws -> Data {
    let image = try renderImage(state: state, preset: preset, size: nil, before: false)
    guard
      let space = CGColorSpace(
        name: profile == .displayP3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)
    else { throw RenderError.message("Color profile unavailable.") }
    let options: [CIImageRepresentationOption: Any] = [
      CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String):
        quality
    ]
    let data: Data?
    switch format {
    case .tiff16:
      data = context.tiffRepresentation(of: image, format: .RGBA16, colorSpace: space, options: [:])
    case .heic:
      if #available(iOS 18.0, macOS 15.0, *) {
        data =
          (try? context.heif10Representation(of: image, colorSpace: space, options: options))
          ?? context.heifRepresentation(
            of: image, format: .RGBA8, colorSpace: space, options: options)
      } else {
        data = context.heifRepresentation(
          of: image, format: .RGBA8, colorSpace: space, options: options)
      }
    case .jpeg: data = context.jpegRepresentation(of: image, colorSpace: space, options: options)
    }
    guard let data else {
      throw RenderError.message("This export format is unavailable on this device.")
    }
    return data
  }
}
