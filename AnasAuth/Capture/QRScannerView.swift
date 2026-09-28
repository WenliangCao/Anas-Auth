import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// 系统原生扫码视图（VisionKit DataScanner），自带取景指引与高亮。
struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    /// 扫码器无法工作（多为相机权限被拒）
    let onError: () -> Void

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
        context.coordinator.parent = scanner
        // 启动失败（相机权限被拒/相机被占用等）不静默吞掉，
        // 与 delegate 的 becameUnavailableWithError 走同一出口，上抛到引导页
        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.reportScannerError(error)
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onError: onError)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onCodeScanned: (String) -> Void
        private let onError: () -> Void
        private var hasDelivered = false
        weak var parent: DataScannerViewController?

        init(onCodeScanned: @escaping (String) -> Void, onError: @escaping () -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onError = onError
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

        /// 相机不可用（权限被拒、相机被占用等）：上抛错误让外层引导用户去设置
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            reportScannerError(error)
        }

        /// 统一错误出口：保证只上报一次，之后进入引导页
        func reportScannerError(_ error: Error) {
            guard !hasDelivered else { return }
            hasDelivered = true
            onError()
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

/// 全屏扫码页：处理权限拒绝引导、关闭按钮
struct ScannerScreen: View {
    let onPayload: (String) -> Void
    let onCancel: () -> Void

    @State private var cameraDenied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if QRScannerView.isAvailable && !cameraDenied {
                // 扫码器内部错误（多为相机权限被拒）→ 展示引导页
                QRScannerView(onCodeScanned: onPayload, onError: { cameraDenied = true })
                    .ignoresSafeArea()
            } else {
                deniedView
            }
        }
        // 从设置里授权/相机被释放后回到前台：重新尝试扫码
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, cameraDenied, QRScannerView.isAvailable {
                cameraDenied = false
            }
        }
        .navigationTitle("Point Camera at QR Code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Camera Unavailable", systemImage: "camera.badge.ellipsis")
        } description: {
            Text("Allow Anas Auth to use the camera in Settings, then come back and try again.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
