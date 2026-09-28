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
    @State private var exportDocument: ExportDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var importResultMessage: String?
    @State private var importPasswordQuery: ImportPasswordQuery?

    /// 待导入文件的内容与是否加密
    private struct ImportPasswordQuery: Identifiable {
        let id = UUID()
        let data: Data
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("安全") {
                    Toggle("应用锁", isOn: $lockManager.isEnabled)
                }

                Section {
                    Button {
                        showingExportPasswordPrompt = true
                    } label: {
                        Label("导出备份（\(entries.count) 条）", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(.primary)
                    .disabled(entries.isEmpty)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("从文件导入", systemImage: "square.and.arrow.down")
                    }
                    .foregroundStyle(.primary)
                } header: {
                    Text("备份")
                } footer: {
                    Text("加密备份的密码丢失后无法恢复。")
                }
                // 去掉强调色：按钮文字和图标都用正文色
                .tint(.primary)

                Section {
                    LabeledContent("版本", value: appVersion)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .data,
                defaultFilename: "auth-backup.authbackup"
            ) { _ in }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json, .data, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(item: $importPasswordQuery) { query in
                ImportPasswordView(data: query.data) { password in
                    importPasswordQuery = nil
                    performImport(data: query.data, password: password)
                } onCancel: {
                    importPasswordQuery = nil
                }
            }
            .sheet(isPresented: $showingExportPasswordPrompt) {
                ExportPasswordView { password in
                    showingExportPasswordPrompt = false
                    exportJSON(password: password)
                } onCancel: { password in
                    showingExportPasswordPrompt = false
                    if let password {
                        exportJSON(password: password) // 用户明确选择不加密
                    }
                }
            }
            .alert("导入结果", isPresented: showImportResult) {
                Button("好") { importResultMessage = nil }
            } message: {
                Text(importResultMessage ?? "")
            }
        }
    }

    @State private var showingExportPasswordPrompt = false

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var showImportResult: Binding<Bool> {
        Binding(
            get: { importResultMessage != nil },
            set: { if !$0 { importResultMessage = nil } }
        )
    }

    private func exportJSON(password: String?) {
        let codes = entries.map { $0.toOTPCode() }
        do {
            let data: Data
            if let password, !password.isEmpty {
                data = try ExportService.makeEncryptedJSON(from: codes, password: password)
            } else {
                data = try ExportService.makeJSON(from: codes)
            }
            exportDocument = ExportDocument(data: data)
            showingExporter = true
        } catch {
            importResultMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else {
            importResultMessage = "导入失败：无法读取文件。"
            return
        }
        if ImportService.isEncryptedBackup(data) {
            importPasswordQuery = ImportPasswordQuery(data: data)
        } else {
            performImport(data: data, password: nil)
        }
    }

    private func performImport(data: Data, password: String?) {
        do {
            let codes = try ImportService.importCodes(fromFileContents: data, password: password)
            let existing = (try? modelContext.fetch(FetchDescriptor<CodeEntry>())) ?? []
            let (unique, skipped) = ImportService.filteringExisting(codes, in: existing)
            for code in unique {
                modelContext.insert(CodeEntry(code: code))
            }
            if skipped > 0 {
                importResultMessage = "成功导入 \(unique.count) 条，跳过 \(skipped) 条已存在的。"
            } else {
                importResultMessage = "成功导入 \(unique.count) 条验证码。"
            }
        } catch BackupCrypto.CryptoError.wrongPassword {
            importResultMessage = "密码不正确，导入失败。"
        } catch {
            importResultMessage = "导入失败：文件内容不是支持的格式。"
        }
    }
}

/// 导出时的密码询问：输入密码加密导出，或明确选择"不加密"
private struct ExportPasswordView: View {
    let onEncrypt: (String) -> Void
    let onCancel: (String?) -> Void

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
                    SecureField("设置密码", text: $password)
                    SecureField("再次输入密码", text: $confirmation)
                    if !confirmation.isEmpty && !passwordsMatch {
                        Text("两次输入的密码不一致")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("加密备份")
                } footer: {
                    Text("密码丢失后无法恢复备份。")
                }
                Section {
                    Button("不加密，直接导出", role: .destructive) {
                        onCancel(password.isEmpty ? nil : "___skip___")
                        dismiss()
                    }
                }
            }
            .navigationTitle("导出备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel(nil)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("加密导出") {
                        onEncrypt(password)
                        dismiss()
                    }
                    .disabled(!passwordsMatch)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// 导入加密备份时的密码输入
private struct ImportPasswordView: View {
    let data: Data
    let onImport: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var wrongPassword = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("备份密码", text: $password)
                    if wrongPassword {
                        Text("密码不正确")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("输入密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        // 先验证密码，错了留在本页提示
                        if (try? BackupCrypto.decrypt(data, password: password)) != nil {
                            onImport(password)
                            dismiss()
                        } else {
                            wrongPassword = true
                        }
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
