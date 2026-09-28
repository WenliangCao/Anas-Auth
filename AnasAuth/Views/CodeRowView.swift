import SwiftUI
import UIKit

/// 验证码卡片，布局对齐 ente auth 的 CodeWidget：
/// 顶部倒计时进度条 → 发行方/账号 + 品牌图标 → 当前码 + 下一个码。
/// 性能关键设计：
/// - 卡片主体静态，不随时间重渲染（滚动/搜索动画不被打断）
/// - 验证码文本只在周期边界那一刻刷新
/// - 进度条由 Core Animation 驱动，App 不逐帧重画
/// - 输入不变时跳过重算（Equatable：闭包无法比较，只比数据）
/// 紧凑模式的尺寸取自 ente 的 isCompactMode。
struct CodeRowView: View, @MainActor Equatable {
    let entry: CodeEntry
    var compact = false
    /// 刚被复制（卡片淡出反馈）
    var isCopied = false
    /// 轻点"下一个"：TOTP 复制下一个码
    var onCopyNext: () -> Void = {}
    /// HOTP 的前进按钮：计数器 +1
    var onAdvanceCounter: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entry.type == .hotp {
                Color.clear.frame(height: compact ? 1 : 3)
            } else {
                CodeProgressBar(period: entry.period)
                    .frame(height: compact ? 1 : 3)
            }
            header
                .padding(.top, compact ? 4 : 28)
            codes
                .padding(.top, compact ? 0 : 4)
                .padding(.bottom, compact ? 4 : 32)
        }
        .background(Color.codeCardBackground)
        .overlay(alignment: .topTrailing) {
            if entry.pinned {
                PinnedCorner(compact: compact)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(entry.pinned ? 0.12 : 0), radius: 2, y: 2)
        .opacity(isCopied ? 0.35 : 1)
        .animation(.snappy(duration: 0.25), value: isCopied)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tap to copy the code. Touch and hold for more options.")
    }

    /// entry 自身属性的变化由 Observation 追踪，这里只需比较身份与外部输入
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entry === rhs.entry && lhs.compact == rhs.compact && lhs.isCopied == rhs.isCopied
    }

    private var title: String {
        entry.issuer.isEmpty ? entry.accountName : entry.issuer
    }

    private var subtitle: String {
        entry.issuer.isEmpty ? "" : entry.accountName
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: compact ? 0 : 2) {
                Text(title)
                    .font(compact ? .subheadline.weight(.medium) : .title3.weight(.medium))
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
                CodePair(entry: entry, date: .now, compact: compact, trailing: .advance(onAdvanceCounter))
                    .id(entry.counter)
            } else {
                // 起点必须是当前周期的开始（过去的时间）：若用未来的边界做起点，
                // 视图被重算时 context.date 会取到未来的边界，卡片提前显示下一个周期的码
                TimelineView(.periodic(
                    from: Self.currentPeriodStart(period: entry.period),
                    by: TimeInterval(max(entry.period, 1))
                )) { context in
                    CodePair(entry: entry, date: context.date, compact: compact, trailing: .nextCode(onCopyNext))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    /// 当前周期的开始（对齐 Unix 时间戳，所有卡片同相位）
    static func currentPeriodStart(period: Int, now: Date = .now) -> Date {
        let period = TimeInterval(max(period, 1))
        return Date(timeIntervalSince1970: (now.timeIntervalSince1970 / period).rounded(.down) * period)
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
    let compact: Bool
    let trailing: Trailing

    var body: some View {
        if let code = CodeFormatter.formatted(entry: entry, at: date) {
            HStack(alignment: .bottom, spacing: 8) {
                Text(code)
                    .font(.system(size: compact ? 16 : 26).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .transaction { $0.animation = nil }
                Spacer(minLength: 0)
                trailingView
            }
        } else {
            Text(CodeFormatter.invalidReason(entry: entry) ?? String(localized: "Invalid secret"))
                .font(.subheadline)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Next")
                .font(.caption2)
                .foregroundStyle(.secondary)
            switch trailing {
            case .nextCode(let onTap):
                Text(CodeFormatter.formattedNext(entry: entry, at: date) ?? "")
                    .font(.system(size: compact ? 13 : 20).monospacedDigit())
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                    .accessibilityAddTraits(.isButton)
            case .advance(let onTap):
                // borderless：不带按钮底色，和旁边的文字一致
                Button(action: onTap) {
                    Image(systemName: "arrow.forward")
                        .font(compact ? .body : .title2)
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Next code")
            }
        }
    }
}

/// 顶部倒计时进度条：剩余比例 > 40% 为紫色，否则橙色（同 ente）。
/// 用 Core Animation 的无限循环动画：动画在系统渲染进程里跑，App 不逐帧重画，
/// 卡片再多也几乎不耗 CPU
private struct CodeProgressBar: UIViewRepresentable {
    let period: Int

    func makeUIView(context: Context) -> ProgressBarView {
        ProgressBarView()
    }

    func updateUIView(_ view: ProgressBarView, context: Context) {
        view.period = TimeInterval(max(period, 1))
    }
}

private final class ProgressBarView: UIView {
    private static let warningFraction = 0.4

    var period = TimeInterval(OTPGenerator.defaultPeriod) {
        didSet { if period != oldValue { restart() } }
    }

    private let bar = CALayer()
    private var animatedWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        bar.cornerRadius = 2
        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        layer.addSublayer(bar)
        // 动画时钟（mach 时间）在设备休眠时不走，回到前台或系统改时间后要按墙上时间重新对齐
        for name in [UIApplication.willEnterForegroundNotification, UIApplication.significantTimeChangeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(restart), name: name, object: nil)
        }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: ProgressBarView, _) in
            view.restart()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width != animatedWidth else { return }
        restart()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        restart()
    }

    /// 按当前时间重新挂动画：宽度从满到空、剩 40% 时变橙，每个周期无限重复，
    /// 起点对齐 Unix 时间的周期边界（与验证码切换同相位）
    @objc private func restart() {
        bar.removeAllAnimations()
        animatedWidth = bounds.width
        guard window != nil, bounds.width > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bar.bounds = CGRect(x: 0, y: 0, width: 0, height: bounds.height)
        bar.position = CGPoint(x: 0, y: bounds.midY)
        CATransaction.commit()

        let elapsed = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        let cycleStart = bar.convertTime(CACurrentMediaTime(), from: nil) - elapsed

        let width = CABasicAnimation(keyPath: "bounds.size.width")
        width.fromValue = bounds.width
        width.toValue = 0

        let color = CAKeyframeAnimation(keyPath: "backgroundColor")
        color.calculationMode = .discrete
        color.values = [UIColor(Color.entePurple), UIColor.systemOrange].map {
            $0.resolvedColor(with: traitCollection).cgColor
        }
        color.keyTimes = [0, NSNumber(value: 1 - Self.warningFraction), 1]

        for (key, animation) in [("width", width as CAAnimation), ("color", color)] {
            animation.beginTime = cycleStart
            animation.duration = period
            animation.repeatCount = .infinity
            bar.add(animation, forKey: key)
        }
    }
}

/// 置顶标记：右上角三角 + 图钉
private struct PinnedCorner: View {
    let compact: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Triangle()
                .fill(Color.pinnedCorner)
                .frame(width: compact ? 24 : 39, height: compact ? 24 : 39)
            Image(systemName: "pin.fill")
                .font(.system(size: compact ? 7 : 10))
                .foregroundStyle(Color.entePurple)
                .rotationEffect(.degrees(45))
                .padding(compact ? 4 : 6)
        }
        .accessibilityLabel("Pinned")
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
                return String(localized: "The secret contains invalid characters (it may have been damaged during sync or migration)")
            }
        } catch {
            return String(localized: "The secret can’t be parsed")
        }
        // Base32 合法但 HMAC 失败：长度为 0
        if entry.secret.isEmpty { return String(localized: "The secret is empty") }
        return nil
    }
}
