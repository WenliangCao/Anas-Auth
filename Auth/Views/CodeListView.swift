import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CodeListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CodeEntry.createdAt, order: .forward)
    private var entries: [CodeEntry]

    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var entryToEdit: CodeEntry?
    @State private var copiedEntryID: UUID?
    @State private var copiedCode: String?
    @State private var copyFeedbackTask: Task<Void, Never>?


    private var filteredEntries: [CodeEntry] {
        let filtered = searchText.isEmpty
            ? entries
            : entries.filter {
                $0.issuer.localizedCaseInsensitiveContains(searchText)
                    || $0.accountName.localizedCaseInsensitiveContains(searchText)
            }
        // 置顶的排前面，其余按创建时间（Bool 不满足 Comparable，无法写进 SortDescriptor）
        return filtered.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.createdAt < rhs.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("还没有验证码", systemImage: "lock.shield")
                    } description: {
                        Text("点右上角 + 扫码或手动添加你的第一个两步验证码")
                    }
                } else {
                    codeList
                }
            }
            .navigationTitle("验证码")
            .searchable(text: $searchText, prompt: "搜索")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddCodeView()
            }
            .sheet(item: $entryToEdit) { entry in
                EditCodeView(entry: entry)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sensoryFeedback(.success, trigger: copiedEntryID)
            .overlay(alignment: .top) {
                if let copiedCode {
                    copiedToast(code: copiedCode)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    /// 复制成功 toast：显示已复制的码，与剪贴板内容一致
    private func copiedToast(code: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc.fill")
                .foregroundStyle(.secondary)
            Text("已复制 \(code)")
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel("已复制验证码 \(code)")
    }

    private var codeList: some View {
        List {
            ForEach(filteredEntries) { entry in
                CodeRowView(entry: entry, copiedEntryID: copiedEntryID)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        copyCode(of: entry)
                    }
                    .contextMenu {
                        Button {
                            togglePin(entry)
                        } label: {
                            Label(entry.pinned ? "取消置顶" : "置顶",
                                  systemImage: entry.pinned ? "pin.slash" : "pin")
                        }
                        Button {
                            entryToEdit = entry
                        } label: {
                            Label("编辑", systemImage: "pencil")
                        }
                        Button {
                            copyCode(of: entry)
                        } label: {
                            Label("复制验证码", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive) {
                            delete(entry)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            delete(entry)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            togglePin(entry)
                        } label: {
                            Label("置顶", systemImage: "pin")
                        }
                        .tint(.orange)
                    }
            }
        }
    }

    private func copyCode(of entry: CodeEntry) {
        guard let code = try? entry.generateCode() else { return }
        // 验证码是敏感数据：不 Handoff 到其他设备，60 秒后自动过期
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: code]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)]
        )
        // 行内淡出反馈 + 顶部 toast，1.5 秒后消失
        withAnimation(.snappy(duration: 0.25)) {
            copiedEntryID = entry.id
            copiedCode = code
        }
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) {
                copiedEntryID = nil
                copiedCode = nil
            }
        }
        if entry.type == .hotp {
            // HOTP 按计数器推进：复制当前码后自增，下次显示下一个
            entry.counter += 1
        }
    }

    private func togglePin(_ entry: CodeEntry) {
        entry.pinned.toggle()
    }

    private func delete(_ entry: CodeEntry) {
        modelContext.delete(entry)
    }
}
