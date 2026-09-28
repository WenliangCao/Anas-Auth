import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CodeListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CodeEntry.createdAt, order: .forward)
    private var entries: [CodeEntry]

    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var entryToEdit: CodeEntry?
    @State private var copiedEntryID: UUID?
    @State private var copiedCode: String?
    @State private var copyFeedbackTask: Task<Void, Never>?
    @State private var entryToDelete: CodeEntry?
    @AppStorage("codeSortKey") private var sortKey: CodeSortKey = .issuer
    @AppStorage("codeLayout") private var layout: CodeLayout = .standard
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
            .navigationBarTitleDisplayMode(.inline)
            // 原生搜索（iOS 26+ iPhone 规范）：底栏里的搜索按钮，点击后由系统在键盘上方展开
            .searchable(text: $searchText, prompt: "搜索")
            .searchToolbarBehavior(.minimize)
            .toolbar {
                topBar
                bottomBar
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
    }

    /// 顶栏：左侧设置，中间标题，右侧排序
    @ToolbarContentBuilder
    private var topBar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("设置")
        }
        ToolbarItem(placement: .principal) {
            Text("Auth")
                .font(.title2.weight(.heavy))
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
    }

    /// 底栏：左侧系统搜索按钮，右侧添加菜单
    @ToolbarContentBuilder
    private var bottomBar: some ToolbarContent {
        DefaultToolbarItem(kind: .search, placement: .bottomBar)
        ToolbarSpacer(placement: .bottomBar)
        ToolbarItem(placement: .bottomBar) {
            AddCodeMenu()
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

    /// 标签条 + 卡片网格（同 ente）：iPhone 单列，iPad 等宽屏自动多列。
    /// 标签条是滚动内容的一部分，上滑时跟卡片一起滑到顶栏下方，
    /// 顶部用 soft 边缘效果逐渐模糊消失，而不是 hard 的分界线。
    /// 不用 List：List 的行会带来滑动删除和整行高亮，和卡片样式不符
    /// 紧凑模式卡片间距更小、列宽阈值更低（宽屏能放下更多列）
    private var codeList: some View {
        let compact = layout == .compact
        let spacing: CGFloat = compact ? 12 : 16
        return ScrollView {
            VStack(spacing: 8) {
                TagFilterBar(tags: allTags, selectedTag: $selectedTag)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: compact ? 280 : 340), spacing: spacing)],
                    spacing: spacing
                ) {
                    ForEach(filteredEntries) { entry in
                        codeCard(entry)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func codeCard(_ entry: CodeEntry) -> some View {
        CodeRowView(
            entry: entry,
            compact: layout == .compact,
            copiedEntryID: copiedEntryID,
            onCopyNext: { copyNextCode(of: entry) },
            onAdvanceCounter: { entry.counter += 1 }
        )
        // 点击区域与长按预览都只是卡片本身
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
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

