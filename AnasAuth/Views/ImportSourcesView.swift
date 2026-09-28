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
        .navigationTitle("Import from Other Apps")
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
            case .incorrectPassword: String(localized: "Incorrect Password")
            case .failure, .invalidEntry: String(localized: "Import Failed")
            case .entryDetail: String(localized: "Unreadable Entry")
            case .confirmGoogle: "Google Authenticator"
            case .finished: String(localized: "Import Complete")
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
                            "Received \(googleTracker.receivedCount) of \(googleTracker.expectedCount) QR codes. Scan or choose the next one.",
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
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isWorking {
                    ProgressView("Please wait…")
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
                Button("Scan QR Code") { showingScanner = true }
                    .glassButtonStyle()
                Button("Choose Image") { showingPhotoPicker = true }
                    .glassButtonStyle()
            } else {
                Button("Choose File") { showingFilePicker = true }
                    .glassButtonStyle()
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
            SecureField("Password", text: $password)
            Button("Import") { runPendingFile(password: password) }
            Button("Cancel", role: .cancel) { pendingFile = nil }
        case .incorrectPassword:
            // 与 ente 一致：密码错了继续让用户重试
            Button("Try Again") { askPassword() }
            Button("Cancel", role: .cancel) { pendingFile = nil }
        case .invalidEntry(_, let entry):
            Button("View Entry") { present(.entryDetail(entry)) }
            Button("OK", role: .cancel) {}
        case .confirmGoogle(let codes):
            Button("Import") { save(codes) }
            Button("Cancel", role: .cancel) {}
        case .finished:
            Button("OK") { dismiss() }
        case .failure, .entryDetail:
            Button("OK", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func alertMessage(_ alert: ImportAlert) -> some View {
        switch alert {
        case .password: Text(source.passwordPrompt)
        case .incorrectPassword: Text("Please check your password and try again.")
        case .failure(let message): Text(message)
        case .invalidEntry(let reason, _): Text(reason)
        case .entryDetail(let entry): Text(entry)
        case .confirmGoogle(let codes): Text("Codes found in Google Authenticator: \(codes.count). Import them?")
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
        isWorking = true
        Task {
            let read = await Task.detached { Result { try ImportService.readFile(at: url) } }.value
            isWorking = false
            switch read {
            case .success(let data):
                pendingFile = (data, url.lastPathComponent)
                runPendingFile(password: nil)
            case .failure(ImportError.fileTooLarge):
                present(.failure(String(localized: "The selected file is too large.")))
            case .failure:
                present(.failure(String(localized: "Couldn’t read the selected file.")))
            }
        }
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
            present(.invalidEntry(reason: String(localized: "One entry couldn’t be read: \(reason)"), entry: entry))
        } else if let error = error as? LocalizedError, let message = error.errorDescription {
            present(.failure(message))
        } else if case ImportCrypto.CryptoError.kdfFailed = error {
            present(.failure(String(localized: "Not enough memory to decrypt. Close other apps and try again.")))
        } else {
            present(.failure(String(localized: "Couldn’t parse the selected file.")))
        }
    }

    // MARK: - Google Authenticator

    private func handleGoogleImages(_ items: [PhotosPickerItem]) async {
        var payloads: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            // 大图识别要几百毫秒，放到后台
            if let payload = await Task.detached(operation: { QRImageDecoder.decode(imageData: data) }).value {
                payloads.append(payload)
            }
        }
        handleGooglePayloads(payloads)
    }

    private func handleGooglePayloads(_ payloads: [String]) {
        guard !payloads.isEmpty else {
            present(.failure(String(localized: "No QR code found in the image.")))
            return
        }
        for payload in payloads {
            guard payload.hasPrefix("otpauth-migration://"),
                  let migration = try? GoogleMigrationParser.parseMigration(payload),
                  !migration.codes.isEmpty else {
                present(.failure(String(localized: "Invalid QR code: it isn’t a Google Authenticator transfer QR code.")))
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
            present(.failure(String(localized: "There are no codes to import in this file.")))
            return
        }
        let existing = (try? modelContext.fetch(FetchDescriptor<CodeEntry>())) ?? []
        let (unique, skipped) = ImportService.filteringExisting(codes, in: existing)
        for code in unique {
            modelContext.insert(CodeEntry(code: code))
        }
        try? modelContext.save()
        let summary = skipped > 0
            ? String(localized: "Imported: \(unique.count). Skipped (already added): \(skipped).")
            : String(localized: "Imported: \(unique.count).")
        present(.finished(summary))
    }
}
