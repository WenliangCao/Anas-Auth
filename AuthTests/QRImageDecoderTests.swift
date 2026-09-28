import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing
import UIKit
@testable import Auth

struct QRImageDecoderTests {
    private static func qrPNG(_ message: String) -> Data {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let cgImage = CIContext().createCGImage(image, from: image.extent)!
        return UIImage(cgImage: cgImage).pngData()!
    }

    @Test func decodesOTPAuthQRCode() {
        let url = "otpauth://totp/Amazon:a@b.com?secret=GEZDGNBVGY3TQOJQ&issuer=Amazon"
        let payload = QRImageDecoder.decode(imageData: Self.qrPNG(url))
        #expect(payload == url)
    }

    @Test func returnsNilWithoutQRCode() {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        #expect(QRImageDecoder.decode(imageData: blank) == nil)
    }
}
