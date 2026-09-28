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

    /// 待导入文件的内容与是否加密
    private struct ImportPasswordQuery: Identifiable {
        let id = UUID()
        let data: Data
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    Toggle("App Lock", isOn: $lockManager.isEnabled)
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
            .alert("Import Result", isPresented: showImportResult) {
                Button("OK") { importResultMessage = nil }
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
            importResultMessage = String(localized: "Export failed: \(error.localizedDescription)")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else {
            importResultMessage = String(localized: "Import failed: couldn’t read the file.")
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
                importResultMessage = String(localized: "Imported: \(unique.count). Skipped (already added): \(skipped).")
            } else {
                importResultMessage = String(localized: "Imported: \(unique.count).")
            }
        } catch BackupCrypto.CryptoError.wrongPassword {
            importResultMessage = String(localized: "Incorrect password. Import failed.")
        } catch {
            importResultMessage = String(localized: "Import failed: the file isn’t in a supported format.")
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
                        onCancel(password.isEmpty ? nil : "___skip___")
                        dismiss()
                    }
                }
            }
            .navigationTitle("Export Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel(nil)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export Encrypted") {
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
                    SecureField("Backup Password", text: $password)
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
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
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
