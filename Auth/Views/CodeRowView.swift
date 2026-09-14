import SwiftUI

/// 验证码列表行。性能关键设计：
/// - 行主体完全静态，不随时间重渲染（滚动/搜索动画不再被打断）
/// - 验证码文本只在周期边界那一刻刷新（30 秒一次而非每秒一次）
/// - 倒计时是一个独立的自绘圆环，每秒重画但没有隐式动画
struct CodeRowView: View {
    let entry: CodeEntry
    /// 当前刚被复制的条目 ID（用于行内淡出反馈）
    var copiedEntryID: UUID?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if entry.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(entry.issuer.isEmpty ? entry.accountName : entry.issuer)
                        .font(.headline)
                        .lineLimit(1)
                }
                if !entry.accountName.isEmpty && !entry.issuer.isEmpty {
                    Text(entry.accountName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                codeText
            }
            Spacer(minLength: 8)
            trailingView
        }
        .opacity(isCopied ? 0.35 : 1)
        .animation(.snappy(duration: 0.25), value: isCopied)
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点复制验证码，长按查看更多操作")
    }

    private var isCopied: Bool {
        copiedEntryID == entry.id
    }

    @ViewBuilder
    private var codeText: some View {
        if entry.type == .hotp {
            // counter 是行内容的唯一输入：复制推进计数器后，SwiftData 变更
            // 触发本行重新求值，新 counter 生成新码，显示永远与剪贴板一致
            if let code = CodeFormatter.formatted(entry: entry, at: .now) {
                Text(code)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.primary)
                    .id(entry.counter)
                    .transaction { $0.animation = nil }
            } else if let reason = CodeFormatter.invalidReason(entry: entry) {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else {
                Text(String(localized: "无效密钥"))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.red)
            }
        } else {
            PeriodBoundaryCodeText(entry: entry)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        if entry.type == .hotp {
            Image(systemName: "number.circle")
                .foregroundStyle(.secondary)
        } else {
            CountdownRingView(period: entry.period)
        }
    }
}

/// 只在 TOTP 周期边界刷新的验证码文本
private struct PeriodBoundaryCodeText: View {
    let entry: CodeEntry

    var body: some View {
        TimelineView(.periodic(
            from: Self.nextBoundary(period: entry.period),
            by: TimeInterval(max(entry.period, 1))
        )) { context in
            let code = CodeFormatter.formatted(entry: entry, at: context.date)
            if let code {
                Text(code)
                    .font(.title3.monospacedDigit())
            } else if let reason = CodeFormatter.invalidReason(entry: entry) {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            } else {
                Text(String(localized: "无效密钥"))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.red)
            }
        }
    }

    /// 下一个周期边界（对齐 Unix 时间戳，所有行同相位）
    static func nextBoundary(period: Int) -> Date {
        let period = TimeInterval(max(period, 1))
        let now = Date().timeIntervalSince1970
        return Date(timeIntervalSince1970: (now / period).rounded(.up) * period)
    }
}

/// 自绘倒计时圆环：每秒对齐刷新，无隐式动画开销
private struct CountdownRingView: View {
    let period: Int

    var body: some View {
        TimelineView(.periodic(from: Self.nextWholeSecond(), by: 1)) { context in
            let remaining = OTPGenerator.remainingSeconds(at: context.date, period: period)
            let fraction = Double(remaining) / Double(max(period, 1))
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        remaining <= 5 ? Color.red : Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(remaining)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
        }
    }

    static func nextWholeSecond() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.up))
    }
}

enum CodeFormatter {
    /// 当前验证码，格式化为每 3 位一组，便于阅读
    static func formatted(entry: CodeEntry, at date: Date) -> String? {
        guard let code = try? entry.generateCode(at: date) else { return nil }
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
