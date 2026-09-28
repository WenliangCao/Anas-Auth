import CoreImage
import Foundation

/// 从相册图片中识别二维码（截图里的二维码、保存的迁移码等）。
/// 用 CIDetector 而非 Vision：Vision 的条码检测在模拟器上不可用。
enum QRImageDecoder {
    /// 返回图中第一个二维码的文本内容，没有则为 nil
    static func decode(imageData: Data) -> String? {
        guard let image = CIImage(data: imageData, options: [.applyOrientationProperty: true]),
              let detector = CIDetector(
                  ofType: CIDetectorTypeQRCode,
                  context: nil,
                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
              ) else { return nil }
        return detector.features(in: image)
            .lazy
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            .first
    }
}
