import SwiftUI
import UniformTypeIdentifiers
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
        context.coordinator.parent = scanner
        // 启动失败（相机权限被拒/相机被占用等）不静默吞掉，
        // 交给 delegate 的 didFailWithError 上抛到引导页
        do {
            try scanner.startScanning()
        } catch {
            context.coordinator.reportScannerError(error)
        }
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
        weak var parent: DataScannerViewController?

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

        /// 相机不可用（常见于权限被拒）：上抛错误让外层引导用户去设置
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didFailWithError error: Error
        ) {
            reportScannerError(error)
        }

        /// 统一错误出口：保证只上报一次，之后进入引导页
        func reportScannerError(_ error: Error) {
            guard !hasDelivered else { return }
            hasDelivered = true
            onCodeScanned("\u{0}SCANNER_ERROR:\(error.localizedDescription)")
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

    var body: some View {
        ZStack {
            if QRScannerView.isAvailable && !cameraDenied {
                QRScannerView { payload in
                    // 扫码器内部错误（多为相机权限被拒）→ 展示引导页
                    if payload.hasPrefix("\u{0}SCANNER_ERROR:") {
                        cameraDenied = true
                    } else {
                        onPayload(payload)
                    }
                }
                .ignoresSafeArea()
            } else {
                deniedView
            }
        }
        .navigationTitle("对准二维码")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { onCancel() }
            }
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("无法访问相机", systemImage: "camera.badge.ellipsis")
        } description: {
            Text("请到系统设置中允许 Auth 使用相机，然后返回重试。")
        } actions: {
            Button("打开系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
