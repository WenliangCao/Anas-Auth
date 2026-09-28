import PhotosUI
import SwiftData
import SwiftUI

/// 右下角展开式添加按钮（对齐 ente 的 SpeedDial）：
/// 扫描二维码 / 手动输入 / 从相册导入。展开时半透明遮罩覆盖全屏。
struct AddCodeMenu: View {
    @Environment(\.modelContext) private var modelContext

    @State private var isExpanded = false
    @State private var showingScanner = false
    @State private var showingManualEntry = false
    @State private var showingPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var importError: String?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Color(.systemBackground)
                    .opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture { toggle() }
                    .transition(.opacity)
            }
            VStack(alignment: .trailing, spacing: 12) {
                if isExpanded {
                    // 顺序与 ente 一致：离主按钮最近的是扫码
                    Group {
                        item("从相册导入", systemImage: "photo.on.rectangle") {
                            showingPhotoPicker = true
                        }
                        item("手动输入详细信息", systemImage: "keyboard") {
                            showingManualEntry = true
                        }
                        // 相机不可用时 ScannerScreen 自带引导页
                        item("扫描二维码", systemImage: "qrcode") {
                            showingScanner = true
                        }
                    }
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
                }
                mainButton
            }
            .padding(.trailing, 16)
            .padding(.bottom, 8)
        }
        // 撑满全屏把按钮推到右下角；空白区域不拦截触摸
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
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

    private var mainButton: some View {
        Button(action: toggle) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .regular))
                .rotationEffect(.degrees(isExpanded ? 45 : 0))
                .frame(width: 60, height: 60)
                .foregroundStyle(Color.fabForeground)
                .background(Color.fabBackground, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "关闭" : "添加验证码")
    }

    private func item(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            toggle()
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body)
                    .padding(12)
                    .background(Color.fabBackground, in: RoundedRectangle(cornerRadius: 8))
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                    .frame(width: 48, height: 48)
                    .background(Color.fabBackground, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    // 与主按钮中心对齐
                    .padding(.trailing, 6)
            }
            .foregroundStyle(Color.fabForeground)
        }
        .buttonStyle(.plain)
    }

    private func toggle() {
        withAnimation(.spring(duration: 0.3, bounce: 0.3)) {
            isExpanded.toggle()
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
