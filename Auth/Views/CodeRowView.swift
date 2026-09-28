import SwiftUI

/// 验证码卡片，布局对齐 ente auth 的 CodeWidget：
/// 顶部倒计时进度条 → 发行方/账号 + 品牌图标 → 当前码 + 下一个码。
/// 性能关键设计：
/// - 卡片主体静态，不随时间重渲染（滚动/搜索动画不被打断）
/// - 验证码文本只在周期边界那一刻刷新
/// - 进度条是独立的 Canvas，只有它按帧重画
struct CodeRowView: View {
    let entry: CodeEntry
    /// 当前刚被复制的条目 ID（用于卡片淡出反馈）
    var copiedEntryID: UUID?
    /// 轻点"下一个"：TOTP 复制下一个码
    var onCopyNext: () -> Void = {}
    /// HOTP 的前进按钮：计数器 +1
    var onAdvanceCounter: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.type == .hotp {
                Color.clear.frame(height: 3)
            } else {
                CodeProgressBar(period: entry.period)
                    .frame(height: 3)
            }
            header
                .padding(.top, 28)
            codes
                .padding(.top, 4)
                .padding(.bottom, 32)
        }
        .background(Color.codeCardBackground)
        .overlay(alignment: .topTrailing) {
            if entry.pinned {
                PinnedCorner()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(entry.pinned ? 0.12 : 0), radius: 2, y: 2)
        .opacity(isCopied ? 0.35 : 1)
        .animation(.snappy(duration: 0.25), value: isCopied)
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点复制验证码，长按查看更多操作")
    }

    private var isCopied: Bool {
        copiedEntryID == entry.id
    }

    private var title: String {
        entry.issuer.isEmpty ? entry.accountName : entry.issuer
    }

    private var subtitle: String {
        entry.issuer.isEmpty ? "" : entry.accountName
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.medium))
                    .lineLimit(1)
                // 账号为空也占一行，保证所有卡片等高
                Text(subtitle.isEmpty ? " " : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            IssuerIconView(issuer: title, iconID: entry.iconID)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var codes: some View {
        Group {
            if entry.type == .hotp {
                // counter 是 HOTP 码的唯一输入：计数器变更触发重新求值
                CodePair(entry: entry, date: .now, trailing: .advance(onAdvanceCounter))
                    .id(entry.counter)
            } else {
                TimelineView(.periodic(
                    from: Self.nextBoundary(period: entry.period),
                    by: TimeInterval(max(entry.period, 1))
                )) { context in
                    CodePair(entry: entry, date: context.date, trailing: .nextCode(onCopyNext))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// 下一个周期边界（对齐 Unix 时间戳，所有卡片同相位）
    static func nextBoundary(period: Int) -> Date {
        let period = TimeInterval(max(period, 1))
        let now = Date().timeIntervalSince1970
        return Date(timeIntervalSince1970: (now / period).rounded(.up) * period)
    }
}

/// 当前码（左）+ 下一个码 / HOTP 前进按钮（右）
private struct CodePair: View {
    enum Trailing {
        case nextCode(() -> Void)
        case advance(() -> Void)
    }

    let entry: CodeEntry
    let date: Date
    let trailing: Trailing

    var body: some View {
        if let code = CodeFormatter.formatted(entry: entry, at: date) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(code)
                    .font(.system(size: 26).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .transaction { $0.animation = nil }
                Spacer(minLength: 0)
                trailingView
            }
        } else {
            Text(CodeFormatter.invalidReason(entry: entry) ?? String(localized: "无效密钥"))
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("下一个")
                .font(.caption2)
                .foregroundStyle(.secondary)
            switch trailing {
            case .nextCode(let onTap):
                Text(CodeFormatter.formattedNext(entry: entry, at: date) ?? "")
                    .font(.system(size: 20).monospacedDigit())
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                    .accessibilityAddTraits(.isButton)
            case .advance(let onTap):
                // borderless：避免 List 把整行当成按钮
                Button(action: onTap) {
                    Image(systemName: "arrow.forward")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("下一个验证码")
            }
        }
    }
}

/// 顶部倒计时进度条：剩余比例 > 40% 为紫色，否则橙色（同 ente）
private struct CodeProgressBar: View {
    let period: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let period = TimeInterval(max(period, 1))
            let elapsed = context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: period)
            let progress = (period - elapsed) / period
            Canvas { canvas, size in
                let rect = CGRect(x: 0, y: 0, width: size.width * progress, height: size.height)
                canvas.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(progress > 0.4 ? .entePurple : .orange)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// 置顶标记：右上角三角 + 图钉
private struct PinnedCorner: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Triangle()
                .fill(Color.pinnedCorner)
                .frame(width: 39, height: 39)
            Image(systemName: "pin.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.entePurple)
                .rotationEffect(.degrees(45))
                .padding(6)
        }
        .accessibilityLabel("已置顶")
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}

enum CodeFormatter {
    /// 当前验证码，格式化为每 3 位一组，便于阅读
    static func formatted(entry: CodeEntry, at date: Date) -> String? {
        guard let code = try? entry.generateCode(at: date) else { return nil }
        return format(code: code, type: entry.type)
    }

    /// 下一个验证码（TOTP 为下一周期，HOTP 为计数器 +1）
    static func formattedNext(entry: CodeEntry, at date: Date) -> String? {
        guard let code = try? entry.generateNextCode(at: date) else { return nil }
        return format(code: code, type: entry.type)
    }

    static func format(code: String, type: OTPType) -> String {
        guard type != .steam else { return code }
        var result = ""
        for (index, character) in code.enumerated() {
            if index > 0 && index % 3 == 0 { result.append(" ") }
            result.append(character)
        }
        return result
    }

    /// 无效密钥的具体原因，供 UI 展示（返回 nil 表示密钥有效）
    static func invalidReason(entry: CodeEntry) -> String? {
        do {
            _ = try Base32.decode(entry.secret)
        } catch let error as Base32Error {
            switch error {
            case .invalidCharacter:
                return "密钥包含非法字符（同步或迁移时可能损坏）"
            }
        } catch {
            return "密钥无法解析"
        }
        // Base32 合法但 HMAC 失败：长度为 0
        if entry.secret.isEmpty { return "密钥为空" }
        return nil
    }
}
