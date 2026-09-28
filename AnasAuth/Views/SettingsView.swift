import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 用于 fileExporter 的备份文档（明文 JSON 或加密二进制）
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [CodeEntry]

    @State private var lockManager = AppLockManager.shared
    @AppStorage("codeLayout") private var layout: CodeLayout = .standard
    @State private var exportDocument: ExportDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var importResultMessage: String?
    @State private var importPasswordQuery: ImportPasswordQuery?
    @State private var showingPasscodeRequired = false
    @State private var showingExportPasswordPrompt = false
    @State private var exportChoice: ExportChoice?
    @State private var isExporting = false
    /// 密码页里导入完成后的结果，等密码页收起后再弹
    @State private var pendingImportMessage: String?

    /// 待输入密码的加密备份
    private struct ImportPasswordQuery: Identifiable {
        let id = UUID()
        let data: Data
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    Toggle("App Lock", isOn: appLockBinding)
                }

                Section {
                    Picker("Layout", selection: $layout) {
                        ForEach(CodeLayout.allCases) { layout in
                            Text(layout.title).tag(layout)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Compact mode uses smaller cards and text, so more codes fit on screen.")
                }

                Section {
                    Button {
                        showingExportPasswordPrompt = true
                    } label: {
                        Label("Export Backup (\(entries.count))", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(.primary)
                    .disabled(entries.isEmpty)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import from Backup File", systemImage: "square.and.arrow.down")
                    }
                    .foregroundStyle(.primary)

                    NavigationLink {
                        ImportSourcesView()
                    } label: {
                        Label("Import from Other Apps", systemImage: "arrow.down.app")
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("Backup")
                } footer: {
                    Text("An encrypted backup can’t be restored if you lose its password.")
                }
                // 去掉强调色：按钮文字和图标都用正文色
                .tint(.primary)

                Section {
                    LabeledContent("Version", value: appVersion)
                    NavigationLink("Open Source Licenses") {
                        LicensesView()
                    }
                } footer: {
                    Text("Anas Auth is open source under the AGPL-3.0 license.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .data,
                defaultFilename: "anas-auth-backup.anasauth"
            ) { _ in }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json, .data, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(item: $importPasswordQuery, onDismiss: showPendingImportResult) { query in
                ImportPasswordView { password in
                    // nil = 密码错误，留在密码页重试
                    guard let message = await importBackup(query.data, password: password) else { return false }
                    pendingImportMessage = message
                    return true
                }
            }
            // 密码页完全收起后再弹保存面板：两个弹出层同时动画时保存面板可能弹不出来
            .sheet(isPresented: $showingExportPasswordPrompt, onDismiss: startExport) {
                ExportPasswordView { exportChoice = $0 }
            }
            .overlay {
                if isExporting {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .disabled(isExporting)
            .alert("Set a Device Passcode", isPresented: $showingPasscodeRequired) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("To use App Lock, first set a passcode in the Settings app under Face ID & Passcode.")
            }
            .alert("Import Result", isPresented: showImportResult) {
                Button("OK") { importResultMessage = nil }
            } message: {
                Text(importResultMessage ?? "")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    /// 开启要先验证身份（设备没设密码则提示去设置），关闭直接关
    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { lockManager.isEnabled },
            set: { isOn in
                if !isOn {
                    lockManager.disable()
                } else if AppLockManager.isDevicePasscodeSet {
                    Task { await lockManager.enable() }
                } else {
                    showingPasscodeRequired = true
                }
            }
        )
    }

    private var showImportResult: Binding<Bool> {
        Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )
    }

    /// 加密要跑 Argon2（零点几秒），放到后台，期间显示进度
    private func startExport() {
        guard let choice = exportChoice else { return }
        exportChoice = nil
        let codes = entries.map { $0.toOTPCode() }
        isExporting = true
        Task {
            let result = await Task.detached {
                Result {
                    switch choice {
                    case .encrypted(let password): try ExportService.makeEncryptedJSON(from: codes, password: password)
                    case .plain: try ExportService.makeJSON(from: codes)
                    }
                }
            }.value
            isExporting = false
            switch result {
            case .success(let data):
                exportDocument = ExportDocument(data: data)
                showingExporter = true
            case .failure(let error):
                importResultMessage = String(localized: "Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        Task {
            let read = await Task.detached { Result { try ImportService.readFile(at: url) } }.value
            switch read {
            case .success(let data) where ImportService.isEncryptedBackup(data):
                importPasswordQuery = ImportPasswordQuery(data: data)
            case .success(let data):
                importResultMessage = await importBackup(data, password: nil)
            case .failure(ImportError.fileTooLarge):
                importResultMessage = String(localized: "Import failed: the file is too large.")
            case .failure:
                importResultMessage = String(localized: "Import failed: couldn’t read the file.")
            }
        }
    }

    private func showPendingImportResult() {
        importResultMessage = pendingImportMessage
        pendingImportMessage = nil
    }

    /// 解密与解析放后台（加密备份要跑 Argon2），写库回到主线程。
    /// 返回给用户看的结果；密码错误返回 nil
    private func importBackup(_ data: Data, password: String?) async -> String? {
        let result = await Task.detached {
            Result { try ImportService.importCodes(fromFileContents: data, password: password) }
        }.value
        switch result {
        case .success(let codes):
            let existing = (try? modelContext.fetch(FetchDescriptor<CodeEntry>())) ?? []
            let (unique, skipped) = ImportService.filteringExisting(codes, in: existing)
            for code in unique {
                modelContext.insert(CodeEntry(code: code))
            }
            return skipped > 0
                ? String(localized: "Imported: \(unique.count). Skipped (already added): \(skipped).")
                : String(localized: "Imported: \(unique.count).")
        case .failure(BackupCrypto.CryptoError.wrongPassword):
            return nil
        case .failure(ImportCrypto.CryptoError.kdfFailed):
            return String(localized: "Not enough memory to decrypt. Close other apps and try again.")
        case .failure:
            return String(localized: "Import failed: the file isn’t in a supported format.")
        }
    }
}

/// 导出方式：加密，或用户明确选择不加密
private enum ExportChoice {
    case encrypted(password: String)
    case plain
}

/// 导出时的密码询问：输入密码加密导出，或明确选择"不加密"；取消则什么都不选
private struct ExportPasswordView: View {
    let onChoose: (ExportChoice) -> Void

    @State private var password = ""
    @State private var confirmation = ""
    @Environment(\.dismiss) private var dismiss

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmation
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Set Password", text: $password)
                    SecureField("Confirm Password", text: $confirmation)
                    if !confirmation.isEmpty && !passwordsMatch {
                        Text("The passwords don’t match")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Encrypt Backup")
                } footer: {
                    Text("If you lose the password, the backup can’t be restored.")
                }
                Section {
                    Button("Export Without Encryption", role: .destructive) {
                        onChoose(.plain)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Export Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export Encrypted") {
                        onChoose(.encrypted(password: password))
                        dismiss()
                    }
                    .disabled(!passwordsMatch)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 导入加密备份时的密码输入。解密在这里等结果：密码错了留在本页提示
private struct ImportPasswordView: View {
    /// 返回 false 表示密码错误
    let onImport: (String) async -> Bool

    @State private var password = ""
    @State private var wrongPassword = false
    @State private var isWorking = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Backup Password", text: $password)
                        .onSubmit(submit)
                    if wrongPassword {
                        Text("Incorrect password")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Enter Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Import", action: submit)
                            .disabled(password.isEmpty)
                    }
                }
            }
            .disabled(isWorking)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isWorking)
    }

    private func submit() {
        guard !password.isEmpty, !isWorking else { return }
        isWorking = true
        wrongPassword = false
        Task {
            if await onImport(password) {
                dismiss()
            } else {
                wrongPassword = true
                isWorking = false
            }
        }
    }
}
