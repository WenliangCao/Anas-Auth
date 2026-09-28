import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CodeListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CodeEntry.createdAt, order: .forward)
    private var entries: [CodeEntry]

    @State private var searchText = ""
    @State private var isSearching = false
    @FocusState private var searchFieldFocused: Bool
    @State private var showingSettings = false
    @State private var entryToEdit: CodeEntry?
    @State private var copiedEntryID: UUID?
    @State private var copiedCode: String?
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var entryToDelete: CodeEntry?
    @AppStorage("codeSortKey") private var sortKey: CodeSortKey = .issuer
    @State private var selectedTag: String?

    /// 所有条目出现过的标签，按自然顺序
    private var allTags: [String] {
        Set(entries.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 选中的标签被删光后自动回到「全部」
    private var activeTag: String? {
        selectedTag.flatMap { allTags.contains($0) ? $0 : nil }
    }

    private var filteredEntries: [CodeEntry] {
        let tagged = activeTag.map { tag in entries.filter { $0.tags.contains(tag) } } ?? entries
        let filtered = searchText.isEmpty
            ? tagged
            : tagged.filter {
                $0.issuer.localizedCaseInsensitiveContains(searchText)
                    || $0.accountName.localizedCaseInsensitiveContains(searchText)
            }
        guard !searchText.isEmpty else {
            return sortKey.sorted(filtered)
        }
        // 搜索态：按相关度排序（命中位置靠前的在前），置顶仅作次级权重
        return filtered.sorted { lhs, rhs in
            let lhsScore = relevanceScore(of: lhs)
            let rhsScore = relevanceScore(of: rhs)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.createdAt < rhs.createdAt
        }
    }

    /// 0 = issuer 前缀命中（最相关），数值越大越不相关
    private func relevanceScore(of entry: CodeEntry) -> Int {
        if entry.issuer.lowercased().hasPrefix(searchText.lowercased()) { return 0 }
        if entry.accountName.lowercased().hasPrefix(searchText.lowercased()) { return 1 }
        if entry.issuer.localizedCaseInsensitiveContains(searchText) { return 2 }
        return 3
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("还没有验证码", systemImage: "lock.shield")
                    } description: {
                        Text("点右下角 + 扫码、手动输入或从相册导入你的第一个两步验证码")
                    }
                } else {
                    codeList
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !entries.isEmpty {
                    TagFilterBar(tags: allTags, selectedTag: $selectedTag)
                        .background(Color(.systemBackground))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { topBar }
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
            .alert(
                "删除验证码",
                isPresented: showDeleteConfirmation
            ) {
                Button("删除", role: .destructive) {
                    if let entryToDelete {
                        delete(entryToDelete)
                    }
                    self.entryToDelete = nil
                }
                Button("取消", role: .cancel) {
                    entryToDelete = nil
                }
            } message: {
                if let entry = entryToDelete {
                    Text("确定删除 \(entry.displayName)？如果这是唯一的验证凭证，删除后可能无法登录该服务。此操作无法撤销。")
                }
            }
        }
        .overlay {
            AddCodeMenu()
        }
    }

    /// 顶栏对齐 ente：左侧菜单（设置），中间标题/搜索框，右侧排序与搜索开关
    @ToolbarContentBuilder
    private var topBar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "line.3.horizontal")
            }
            .accessibilityLabel("设置")
        }
        ToolbarItem(placement: .principal) {
            if isSearching {
                TextField("搜索", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($searchFieldFocused)
                    .submitLabel(.search)
                    .frame(minWidth: 220)
            } else {
                Text("Auth")
                    .font(.title2.weight(.heavy))
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("排序方式", selection: $sortKey) {
                    ForEach(CodeSortKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityLabel("排序方式")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                toggleSearch()
            } label: {
                Image(systemName: isSearching ? "xmark" : "magnifyingglass")
            }
            .accessibilityLabel(isSearching ? "关闭搜索" : "搜索")
        }
    }

    private func toggleSearch() {
        isSearching.toggle()
        if isSearching {
            searchFieldFocused = true
        } else {
            searchText = ""
            searchFieldFocused = false
        }
    }

    private var showDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )
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
                CodeRowView(
                    entry: entry,
                    copiedEntryID: copiedEntryID,
                    onCopyNext: { copyNextCode(of: entry) },
                    onAdvanceCounter: { entry.counter += 1 }
                )
                    .contentShape(Rectangle())
                    // 长按预览只截卡片本身，不带列表行的白底
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
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
                            entryToDelete = entry
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            entryToDelete = entry
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
        .listStyle(.plain)
        // 底部留白，最后一张卡片不被悬浮按钮挡住
        .contentMargins(.bottom, 80, for: .scrollContent)
    }

    private func copyCode(of entry: CodeEntry) {
        guard let code = try? entry.generateCode() else { return }
        copyToPasteboard(code, entry: entry)
    }

    /// 提前复制下一周期的码（仅 TOTP/Steam，HOTP 用前进按钮）
    private func copyNextCode(of entry: CodeEntry) {
        guard entry.type != .hotp, let code = try? entry.generateNextCode() else { return }
        copyToPasteboard(code, entry: entry)
    }

    private func copyToPasteboard(_ code: String, entry: CodeEntry) {
        entry.tapCount += 1
        entry.lastUsedAt = .now
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
    }

    private func togglePin(_ entry: CodeEntry) {
        entry.pinned.toggle()
    }

    private func delete(_ entry: CodeEntry) {
        modelContext.delete(entry)
    }
}
