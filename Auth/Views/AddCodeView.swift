import SwiftUI
import SwiftData

/// 添加入口：扫码（含 Google Authenticator 迁移二维码）或手动输入。
struct AddCodeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingScanner = false
    @State private var showingManualEntry = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                if QRScannerView.isAvailable {
                    Button {
                        showingScanner = true
                    } label: {
                        Label("扫描二维码", systemImage: "qrcode.viewfinder")
                    }
                }
                Button {
                    showingManualEntry = true
                } label: {
                    Label("手动输入密钥", systemImage: "keyboard")
                }
            }
            .navigationTitle("添加验证码")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                scannerScreen
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualEntryView()
            }
            .alert("无法识别", isPresented: showErrorAlert) {
                Button("好") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var showErrorAlert: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    private var scannerScreen: some View {
        NavigationStack {
            ScannerScreen(
                onPayload: { payload in
                    handleScanned(payload)
                },
                onCancel: { showingScanner = false }
            )
        }
    }

    private func handleScanned(_ payload: String) {
        do {
            // 同时兼容 otpauth:// 单条与 otpauth-migration:// 批量迁移
            let codes = try ImportService.importCodes(from: payload)
            let existing = (try? modelContext.fetch(FetchDescriptor<CodeEntry>())) ?? []
            let (unique, skipped) = ImportService.filteringExisting(codes, in: existing)
            for code in unique {
                modelContext.insert(CodeEntry(code: code))
            }
            showingScanner = false
            if unique.isEmpty && skipped > 0 {
                importError = "这些验证码都已存在，没有新内容可添加。"
            } else {
                dismiss()
            }
        } catch {
            showingScanner = false
            importError = "二维码内容不是有效的验证码格式。"
        }
    }
}
