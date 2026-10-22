import CoreImage

extension PhotoRenderer {
  /// Read a small sRGB proxy so histogram work remains bounded during editing.
  func histogram(_ preview: CGImage) -> [Float] {
    let image = CIImage(cgImage: preview)
    let scale = min(1, 256 / max(image.extent.width, image.extent.height))
    let proxy = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let width = max(1, Int(proxy.extent.width))
    let height = max(1, Int(proxy.extent.height))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
      if let address = buffer.baseAddress {
        context.render(
          proxy, toBitmap: address, rowBytes: width * 4,
          bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8,
          colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
      }
    }
    var bins = [Float](repeating: 0, count: 256)
    for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] > 0 {
      let r = Double(pixels[offset])
      let g = Double(pixels[offset + 1])
      let b = Double(pixels[offset + 2])
      let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
      bins[min(255, max(0, Int(luminance)))] += 1
    }
    return bins
  }
}
