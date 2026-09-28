import PhotosUI
import SwiftData
import SwiftUI

/// 底栏右侧的添加按钮（系统 Menu，玻璃样式由工具栏提供）。
/// 扫描二维码 / 手动输入 / 从相册导入。
struct AddCodeMenu: View {
    @Environment(\.modelContext) private var modelContext

    @State private var showingScanner = false
    @State private var showingManualEntry = false
    @State private var showingPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var importError: String?
    @State private var saveError: String?
    /// Google 迁移码账号多时会拆成多张，全部扫完再一起导入
    @State private var googleTracker = GoogleMigrationTracker()
    @State private var googlePending: GooglePending?

    /// 还差批次没扫：提示进度，并记住从哪里继续（相机或相册）
    private struct GooglePending {
        let received: Int
        let expected: Int
        let fromPhotos: Bool
    }

    var body: some View {
        Menu {
            // 相机不可用时 ScannerScreen 自带引导页
            Button("Scan QR Code", systemImage: "qrcode.viewfinder") {
                showingScanner = true
            }
            Button("Enter Manually", systemImage: "keyboard") {
                showingManualEntry = true
            }
            Button("Import from Photos", systemImage: "photo") {
                showingPhotoPicker = true
            }
        } label: {
            Label("Add Code", systemImage: "plus")
        }
        .fullScreenCover(isPresented: $showingScanner) {
            NavigationStack {
                ScannerScreen(
                    onPayload: { payload in
                        showingScanner = false
                        importPayload(payload, fromPhotos: false)
                    },
                    onCancel: { showingScanner = false }
                )
            }
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualEntryView()
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            Task { await importPhoto(item) }
        }
        .alert("Couldn’t Recognize", isPresented: showErrorAlert) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert(Text(verbatim: "Google Authenticator"), isPresented: showGooglePendingAlert, presenting: googlePending) { pending in
            Button("Continue") {
                if pending.fromPhotos { showingPhotoPicker = true } else { showingScanner = true }
            }
            Button("Cancel", role: .cancel) { googleTracker = GoogleMigrationTracker() }
        } message: { pending in
            Text("Received \(pending.received) of \(pending.expected) QR codes. Scan or choose the next one.")
        }
        .alert("Couldn’t Save", isPresented: showSaveErrorAlert) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var showGooglePendingAlert: Binding<Bool> {
        Binding(
            get: { googlePending != nil },
            set: { if !$0 { googlePending = nil } }
        )
    }

    private var showSaveErrorAlert: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        let data = try? await item.loadTransferable(type: Data.self)
        // 大图识别要几百毫秒，放到后台
        let payload = await Task.detached { data.flatMap(QRImageDecoder.decode(imageData:)) }.value
        guard let payload else {
            importError = String(localized: "No QR code found in the image.")
            return
        }
        importPayload(payload, fromPhotos: true)
    }

    /// 扫码与相册共用：兼容 otpauth:// 单条与 otpauth-migration:// 批量迁移
    private func importPayload(_ payload: String, fromPhotos: Bool) {
        let payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let codes: [OTPCode]
        do {
            if payload.hasPrefix("otpauth-migration://") {
                guard let all = try googleTracker.add(GoogleMigrationParser.parseMigration(payload)) else {
                    googlePending = GooglePending(
                        received: googleTracker.receivedCount,
                        expected: googleTracker.expectedCount,
                        fromPhotos: fromPhotos
                    )
                    return
                }
                codes = all
            } else {
                codes = try ImportService.importCodes(from: payload)
            }
        } catch let error as GoogleMigrationTracker.TrackerError {
            googleTracker = GoogleMigrationTracker()
            importError = error.localizedDescription
            return
        } catch {
            importError = String(localized: "The QR code doesn’t contain a valid code.")
            return
        }
        guard !codes.isEmpty else {
            importError = String(localized: "The QR code doesn’t contain a valid code.")
            return
        }
        do {
            let (added, skipped) = try modelContext.addCodes(codes)
            if added == 0 && skipped > 0 {
                importError = String(localized: "These codes already exist. There’s nothing new to add.")
            }
        } catch {
            saveError = CodeStore.saveFailureMessage(error)
        }
    }
}
