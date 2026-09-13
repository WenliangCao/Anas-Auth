import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 用于 fileExporter 的 JSON 文档
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

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

    var body: some View {
        NavigationStack {
            Form {
                Section("安全") {
                    Toggle("\(lockManager.biometryName) 锁定", isOn: $lockManager.isEnabled)
                }

                Section("备份") {
                    Button {
                        exportJSON()
                    } label: {
                        Label("导出 JSON 备份（\(entries.count) 条）", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("从文件导入", systemImage: "square.and.arrow.down")
                    }
                }

                Section("同步") {
                    Label("通过 iCloud 自动同步到你的其他设备", systemImage: "icloud")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0")
                    Link("算法基于开放标准 RFC 4226 / RFC 6238",
                         destination: URL(string: "https://www.rfc-editor.org/rfc/rfc6238")!)
                        .font(.footnote)
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
                contentType: .json,
                defaultFilename: "auth-backup.json"
            ) { _ in }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json, .plainText, .text, .data],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("导入结果", isPresented: .constant(importResultMessage != nil)) {
                Button("好") { importResultMessage = nil }
            } message: {
                Text(importResultMessage ?? "")
            }
        }
    }

    private func exportJSON() {
        let codes = entries.map { $0.toOTPCode() }
        guard let data = try? ExportService.makeJSON(from: codes) else { return }
        exportDocument = ExportDocument(data: data)
        showingExporter = true
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let codes = try ImportService.importCodes(from: text)
            for code in codes {
                modelContext.insert(CodeEntry(code: code))
            }
            importResultMessage = "成功导入 \(codes.count) 条验证码。"
        } catch {
            importResultMessage = "导入失败：文件内容不是支持的格式。"
        }
    }
}
