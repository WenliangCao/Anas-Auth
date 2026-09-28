import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 设置 → 从其他应用导入：来源列表（与 ente 相同的 11 种）
struct ImportSourcesView: View {
    @State private var selectedSource: ImportSource?

    var body: some View {
        List(ImportSource.allCases) { source in
            Button(source.title) { selectedSource = source }
                .foregroundStyle(.primary)
        }
        .navigationTitle("从其他应用导入")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSource) { source in
            ImportGuideView(source: source)
        }
    }
}

/// 单个来源的导入流程：说明 → 选文件（或扫码）→ 按需输入密码 → 去重写入 → 结果
private struct ImportGuideView: View {
    let source: ImportSource

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var showingScanner = false
    @State private var showingPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var pendingFile: (data: Data, name: String)?
    @State private var password = ""
    @State private var isWorking = false
    @State private var alert: ImportAlert?
    @State private var googleTracker = GoogleMigrationTracker()

    private enum ImportAlert {
        case password
        case incorrectPassword
        case failure(String)
        case invalidEntry(reason: String, entry: String)
        case entryDetail(String)
        case confirmGoogle([OTPCode])
        case finished(String)

        var title: String {
            switch self {
            case .password: ""
            case .incorrectPassword: "密码错误"
            case .failure, .invalidEntry: "导入失败"
            case .entryDetail: "无法解析的条目"
            case .confirmGoogle: "Google Authenticator"
            case .finished: "导入完成"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(source.guide)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if source == .googleAuthenticator, googleTracker.expectedCount > 0 {
                        Label(
                            "已收到 \(googleTracker.receivedCount)/\(googleTracker.expectedCount) 张二维码，请继续扫描或选择下一张。",
                            systemImage: "qrcode"
                        )
                        .font(.subheadline)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle(source.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView("请稍候…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .disabled(isWorking)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isWorking)
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.item]) { result in
            handlePickedFile(result)
        }
        .fullScreenCover(isPresented: $showingScanner) {
            NavigationStack {
                ScannerScreen(
                    onPayload: { payload in
                        showingScanner = false
                        handleGooglePayloads([payload])
                    },
                    onCancel: { showingScanner = false }
                )
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItems, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await handleGoogleImages(items) }
        }
        .alert(alert?.title ?? "", isPresented: isShowingAlert, presenting: alert) { alert in
            alertActions(alert)
        } message: { alert in
            alertMessage(alert)
        }
    }

    // MARK: - 按钮与弹窗

    private var actions: some View {
        VStack(spacing: 10) {
            if source == .googleAuthenticator {
                Button("扫描二维码") { showingScanner = true }
                    .buttonStyle(.glass)
                Button("选择图片") { showingPhotoPicker = true }
                    .buttonStyle(.glass)
            } else {
                Button("选择文件") { showingFilePicker = true }
                    .buttonStyle(.glass)
            }
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var isShowingAlert: Binding<Bool> {
        Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })
    }

    @ViewBuilder
    private func alertActions(_ alert: ImportAlert) -> some View {
        switch alert {
        case .password:
            SecureField("密码", text: $password)
            Button("导入") { runPendingFile(password: password) }
            Button("取消", role: .cancel) { pendingFile = nil }
        case .incorrectPassword:
            // 与 ente 一致：密码错了继续让用户重试
            Button("重试") { askPassword() }
            Button("取消", role: .cancel) { pendingFile = nil }
        case .invalidEntry(_, let entry):
            Button("查看条目") { present(.entryDetail(entry)) }
            Button("好", role: .cancel) {}
        case .confirmGoogle(let codes):
            Button("导入") { save(codes) }
            Button("取消", role: .cancel) {}
        case .finished:
            Button("好") { dismiss() }
        case .failure, .entryDetail:
            Button("好", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func alertMessage(_ alert: ImportAlert) -> some View {
        switch alert {
        case .password: Text(source.passwordPrompt)
        case .incorrectPassword: Text("请检查您的密码并重试。")
        case .failure(let message): Text(message)
        case .invalidEntry(let reason, _): Text(reason)
        case .entryDetail(let entry): Text(entry)
        case .confirmGoogle(let codes): Text("要从 Google Authenticator 导入 \(codes.count) 个验证码吗？")
        case .finished(let message): Text(message)
        }
    }

    /// 上一个弹窗消失后再弹下一个，避免 SwiftUI 吞掉连续的 alert
    private func present(_ next: ImportAlert) {
        alert = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            alert = next
        }
    }

    private func askPassword() {
        password = ""
        present(.password)
    }

    // MARK: - 文件导入

    private func handlePickedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            present(.failure("无法读取所选文件。"))
            return
        }
        pendingFile = (data, url.lastPathComponent)
        runPendingFile(password: nil)
    }

    private func runPendingFile(password: String?) {
        guard let file = pendingFile else { return }
        if let password, password.isEmpty {
            askPassword()
            return
        }
        isWorking = true
        let source = source
        Task {
            // Argon2 / scrypt 可能耗时数秒，放到后台
            let result = await Task.detached {
                Result { try source.process(file.data, fileName: file.name, password: password) }
            }.value
            isWorking = false
            switch result {
            case .success(.needsPassword):
                askPassword()
            case .success(.codes(let codes)):
                pendingFile = nil
                save(codes)
            case .failure(ImportProviderError.incorrectPassword):
                present(.incorrectPassword)
            case .failure(let error):
                pendingFile = nil
                show(error)
            }
        }
    }

    private func show(_ error: Error) {
        if case .invalidEntry(let entry, let reason) = error as? ImportProviderError {
            present(.invalidEntry(reason: "有一个条目无法解析：\(reason)", entry: entry))
        } else if let error = error as? LocalizedError, let message = error.errorDescription {
            present(.failure(message))
        } else if case ImportCrypto.CryptoError.kdfFailed = error {
            present(.failure("解密所需内存不足，请关闭其他应用后重试。"))
        } else {
            present(.failure("无法解析选定的文件。"))
        }
    }

    // MARK: - Google Authenticator

    private func handleGoogleImages(_ items: [PhotosPickerItem]) async {
        var payloads: [String] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let payload = QRImageDecoder.decode(imageData: data) {
                payloads.append(payload)
            }
        }
        handleGooglePayloads(payloads)
    }

    private func handleGooglePayloads(_ payloads: [String]) {
        guard !payloads.isEmpty else {
            present(.failure("图片中没有找到二维码。"))
            return
        }
        for payload in payloads {
            guard payload.hasPrefix("otpauth-migration://"),
                  let migration = try? GoogleMigrationParser.parseMigration(payload),
                  !migration.codes.isEmpty else {
                present(.failure("二维码无效：不是 Google Authenticator 的转移二维码。"))
                return
            }
            do {
                if let codes = try googleTracker.add(migration) {
                    present(.confirmGoogle(codes))
                    return
                }
            } catch {
                googleTracker = GoogleMigrationTracker()
                show(error)
                return
            }
        }
    }

    // MARK: - 写入

    private func save(_ codes: [OTPCode]) {
        guard !codes.isEmpty else {
            present(.failure("文件中没有可导入的验证码。"))
            return
        }
        let existing = (try? modelContext.fetch(FetchDescriptor<CodeEntry>())) ?? []
        let (unique, skipped) = ImportService.filteringExisting(codes, in: existing)
        for code in unique {
            modelContext.insert(CodeEntry(code: code))
        }
        try? modelContext.save()
        let summary = skipped > 0
            ? "已导入 \(unique.count) 个验证码，跳过 \(skipped) 个已存在的。"
            : "已导入 \(unique.count) 个验证码。"
        present(.finished(summary))
    }
}
