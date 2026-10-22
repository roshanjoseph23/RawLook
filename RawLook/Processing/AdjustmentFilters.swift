import CoreImage
import CoreImage.CIFilterBuiltins

extension PhotoRenderer {
  func adjusted(_ image: CIImage, _ state: EditState) -> CIImage {
    var result = image
    func value(_ key: Adjustment) -> Float { state.adjustments[key] ?? key.neutralValue }
    if value(.brightness) != 0 || value(.contrast) != 0 || value(.saturation) != 0 {
      let filter = CIFilter.colorControls()
      filter.inputImage = result
      filter.brightness = value(.brightness) * 0.25
      filter.contrast = 1 + value(.contrast)
      filter.saturation = 1 + value(.saturation)
      result = filter.outputImage ?? result
    }
    let brilliance = value(.brilliance)
    if value(.highlights) != 0 || value(.shadows) != 0 || brilliance != 0 {
      let filter = CIFilter.highlightShadowAdjust()
      filter.inputImage = result
      filter.highlightAmount = 1 - value(.highlights) * 0.5 - brilliance * 0.2
      filter.shadowAmount = value(.shadows) + brilliance * 0.25
      result = filter.outputImage ?? result
    }
    if value(.vibrance) != 0 {
      let filter = CIFilter.vibrance()
      filter.inputImage = result
      filter.amount = value(.vibrance)
      result = filter.outputImage ?? result
    }
    if value(.clarity) != 0 || brilliance != 0 {
      let filter = CIFilter.unsharpMask()
      filter.inputImage = result.clampedToExtent()
      filter.radius = Float(max(image.extent.width, image.extent.height)) * 0.015
      filter.intensity = value(.clarity) * 0.35 + brilliance * 0.1
      result = (filter.outputImage ?? result).cropped(to: image.extent)
    }
    if value(.sharpness) != 0 {
      let filter = CIFilter.sharpenLuminance()
      filter.inputImage = result
      filter.sharpness = value(.sharpness)
      result = filter.outputImage ?? result
    }
    if value(.vignette) != 0 {
      let filter = CIFilter.vignette()
      filter.inputImage = result
      filter.intensity = value(.vignette) * 2
      filter.radius = Float(min(image.extent.width, image.extent.height)) * 0.4
      result = filter.outputImage ?? result
    }
    return result
  }
}
