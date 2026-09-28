import PhotosUI
import SwiftData
import SwiftUI

/// 右下角添加按钮：系统 Menu + Liquid Glass 圆形按钮。
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
            Button("扫描二维码", systemImage: "qrcode.viewfinder") {
                showingScanner = true
            }
            Button("手动输入", systemImage: "keyboard") {
                showingManualEntry = true
            }
            Button("从相册导入", systemImage: "photo") {
                showingPhotoPicker = true
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel("添加验证码")
        .padding(.trailing, 20)
        .padding(.bottom, 8)
        // 撑满全屏把按钮推到右下角；空白区域不拦截触摸
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
        .alert("无法识别", isPresented: showErrorAlert) {
            Button("好") { importError = nil }
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
            importError = "图片中没有找到二维码。"
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
                importError = "这些验证码都已存在，没有新内容可添加。"
            }
        } catch {
            importError = "二维码内容不是有效的验证码格式。"
        }
    }
}
