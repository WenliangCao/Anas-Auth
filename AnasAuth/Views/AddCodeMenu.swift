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
                        importPayload(payload)
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
    }

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let payload = QRImageDecoder.decode(imageData: data) else {
            importError = String(localized: "No QR code found in the image.")
            return
        }
        importPayload(payload)
    }

    /// 扫码与相册共用：兼容 otpauth:// 单条与 otpauth-migration:// 批量迁移
    private func importPayload(_ payload: String) {
        do {
            let codes = try ImportService.importCodes(from: payload)
            let existing = (try? modelContext.fetch(FetchDescriptor<CodeEntry>())) ?? []
            let (unique, skipped) = ImportService.filteringExisting(codes, in: existing)
            for code in unique {
                modelContext.insert(CodeEntry(code: code))
            }
            if unique.isEmpty && skipped > 0 {
                importError = String(localized: "These codes already exist. There’s nothing new to add.")
            }
        } catch {
            importError = String(localized: "The QR code doesn’t contain a valid code.")
        }
    }
}
