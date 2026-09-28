import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CodeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \CodeEntry.createdAt, order: .forward)
    private var entries: [CodeEntry]

    @State private var searchText = ""
    @State private var showingSettings = false
    @State private var entryToEdit: CodeEntry?
    @State private var copiedEntryID: UUID?
    @State private var copiedCode: String?
    @State private var copyFeedbackTask: Task<Void, Never>?
    /// 每次复制 +1，作为触感反馈的触发器（连续复制同一条也会震，反馈消失时不会震）
    @State private var copyCount = 0
    /// 复制带来的使用次数/时间先记在这里，离开首页或切到后台时才写库：
    /// 否则按「最近使用/最常用」排序时，卡片会在手指下立刻跳走，每次复制也都触发一次 iCloud 同步
    @State private var pendingUsage: [UUID: PendingUsage] = [:]

    private struct PendingUsage {
        let entry: CodeEntry
        var taps = 0
        var lastUsedAt = Date.distantPast
    }
    @State private var entryToDelete: CodeEntry?
    @AppStorage("codeSortKey") private var sortKey: CodeSortKey = .issuer
    @AppStorage("codeLayout") private var layout: CodeLayout = .standard
    @State private var selectedTag: String?

    /// 所有条目出现过的标签，按自然顺序
    private var allTags: [String] {
        Set(entries.flatMap(\.tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 按标签与搜索词过滤并排序。选中的标签被删光后自动回到「全部」
    private func filteredEntries(tags: [String]) -> [CodeEntry] {
        let activeTag = selectedTag.flatMap { tags.contains($0) ? $0 : nil }
        let tagged = activeTag.map { tag in entries.filter { $0.tags.contains(tag) } } ?? entries
        guard !searchText.isEmpty else {
            return sortKey.sorted(tagged)
        }
        // 搜索态：按相关度排序（命中位置靠前的在前），置顶仅作次级权重。
        // 相关度每条只算一次，不在比较函数里反复计算
        let query = searchText.lowercased()
        let scored = tagged.compactMap { entry in
            relevanceScore(of: entry, query: query).map { (entry: entry, score: $0) }
        }
        return scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            if lhs.entry.pinned != rhs.entry.pinned { return lhs.entry.pinned }
            return lhs.entry.createdAt < rhs.entry.createdAt
        }.map(\.entry)
    }

    /// 0 = issuer 前缀命中（最相关），数值越大越不相关；nil = 不匹配
    private func relevanceScore(of entry: CodeEntry, query: String) -> Int? {
        let issuer = entry.issuer.lowercased()
        let account = entry.accountName.lowercased()
        if issuer.hasPrefix(query) { return 0 }
        if account.hasPrefix(query) { return 1 }
        if entry.issuer.localizedCaseInsensitiveContains(searchText) { return 2 }
        if entry.accountName.localizedCaseInsensitiveContains(searchText) { return 3 }
        return nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Codes Yet", systemImage: "lock.shield")
                    } description: {
                        Text("Tap + to scan a QR code, enter a code manually, or import one from Photos.")
                    }
                } else {
                    codeList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search")
            .toolbar { topBar }
            .modifier(BottomBar())
            .sheet(item: $entryToEdit) { entry in
                EditCodeView(entry: entry)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sensoryFeedback(.success, trigger: copyCount)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { flushUsage() }
            }
            .onDisappear(perform: flushUsage)
            .overlay(alignment: .top) {
                if let copiedCode {
                    copiedToast(code: copiedCode)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .alert(
                "Delete Code",
                isPresented: showDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) {
                    if let entryToDelete {
                        delete(entryToDelete)
                    }
                    self.entryToDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    entryToDelete = nil
                }
            } message: {
                if let entry = entryToDelete {
                    Text("Delete \(entry.displayName)? If this is your only way to sign in, you may lose access to the account. This can’t be undone.")
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
            .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .principal) {
            Text(verbatim: "Anas Auth")
                .font(.title2.weight(.heavy))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort By", selection: $sortKey) {
                    ForEach(CodeSortKey.allCases) { key in
                        Text(key.title).tag(key)
                    }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .accessibilityLabel("Sort By")
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
            Text("Copied \(code)")
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel("Copied code \(code)")
    }

    /// 标签条 + 卡片网格（同 ente）：iPhone 单列，iPad 等宽屏自动多列。
    /// 标签条是滚动内容的一部分，上滑时跟卡片一起滑到顶栏下方，
    /// 顶部用 soft 边缘效果逐渐模糊消失，而不是 hard 的分界线。
    /// 不用 List：List 的行会带来滑动删除和整行高亮，和卡片样式不符
    /// 紧凑模式卡片间距更小、列宽阈值更低（宽屏能放下更多列）
    private var codeList: some View {
        let compact = layout == .compact
        let spacing: CGFloat = compact ? 12 : 16
        let tags = allTags
        let visibleEntries = filteredEntries(tags: tags)
        return ScrollView {
            VStack(spacing: 8) {
                TagFilterBar(tags: tags, selectedTag: $selectedTag)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: compact ? 280 : 340), spacing: spacing)],
                    spacing: spacing
                ) {
                    ForEach(visibleEntries) { entry in
                        codeCard(entry)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
        .softTopScrollEdge()
    }

    private func codeCard(_ entry: CodeEntry) -> some View {
        CodeRowView(
            entry: entry,
            compact: layout == .compact,
            isCopied: copiedEntryID == entry.id,
            onCopyNext: { copyNextCode(of: entry) },
            onAdvanceCounter: { advanceCounter(of: entry) }
        )
        .equatable()
        // 点击区域与长按预览都只是卡片本身
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            copyCode(of: entry)
        }
        // 卡片不是 Button（里面还有「下一个」按钮），给 VoiceOver 补上按钮语义与动作
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { copyCode(of: entry) }
        .accessibilityAction(named: entry.type == .hotp ? Text("Next code") : Text("Copy Next Code")) {
            if entry.type == .hotp {
                advanceCounter(of: entry)
            } else {
                copyNextCode(of: entry)
            }
        }
        .contextMenu {
            Button {
                togglePin(entry)
            } label: {
                Label(entry.pinned ? "Unpin" : "Pin",
                      systemImage: entry.pinned ? "pin.slash" : "pin")
            }
            Button {
                entryToEdit = entry
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button {
                copyCode(of: entry)
            } label: {
                Label("Copy Code", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                entryToDelete = entry
            } label: {
                Label("Delete", systemImage: "trash")
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

    private func advanceCounter(of entry: CodeEntry) {
        if entry.counter < .max { entry.counter += 1 }
    }

    private func copyToPasteboard(_ code: String, entry: CodeEntry) {
        pendingUsage[entry.id, default: PendingUsage(entry: entry)].taps += 1
        pendingUsage[entry.id]?.lastUsedAt = .now
        // 验证码是敏感数据：不 Handoff 到其他设备，60 秒后自动过期
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: code]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)]
        )
        copyCount += 1
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

    private func flushUsage() {
        for usage in pendingUsage.values where !usage.entry.isDeleted {
            usage.entry.tapCount += usage.taps
            usage.entry.lastUsedAt = usage.lastUsedAt
        }
        pendingUsage = [:]
    }

    private func togglePin(_ entry: CodeEntry) {
        entry.pinned.toggle()
    }

    private func delete(_ entry: CodeEntry) {
        modelContext.delete(entry)
    }
}

/// 底栏。iOS 26+：原生搜索按钮（点击后由系统在键盘上方展开）+ 添加菜单；
/// iOS 18–25：搜索框由系统放在导航栏下方，底栏只放添加菜单
private struct BottomBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .searchToolbarBehavior(.minimize)
                .toolbar {
                    DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    ToolbarSpacer(placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        AddCodeMenu()
                    }
                }
        } else {
            content.toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    AddCodeMenu()
                }
            }
        }
    }
}
