import SwiftUI
import VisionKit

/// 系统原生扫码视图（VisionKit DataScanner），自带取景指引与高亮。
struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCodeScanned: (String) -> Void
        private var hasDelivered = false

        init(onCodeScanned: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            deliver(items: addedItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            deliver(items: [item])
        }

        private func deliver(items: [RecognizedItem]) {
            guard !hasDelivered else { return }
            for item in items {
                if case .barcode(let barcode) = item,
                   let payload = barcode.payloadStringValue {
                    hasDelivered = true
                    dataScannerHaptic()
                    onCodeScanned(payload)
                    return
                }
            }
        }

        private func dataScannerHaptic() {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
