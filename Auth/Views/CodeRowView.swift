import SwiftUI

/// 验证码列表行。性能关键设计：
/// - 行主体完全静态，不随时间重渲染（滚动/搜索动画不再被打断）
/// - 验证码文本只在周期边界那一刻刷新（30 秒一次而非每秒一次）
/// - 倒计时是一个独立的自绘圆环，每秒重画但没有隐式动画
struct CodeRowView: View {
    let entry: CodeEntry

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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var codeText: some View {
        if entry.type == .hotp {
            Text(CodeFormatter.formatted(entry: entry, at: .now) ?? String(localized: "无效密钥"))
                .font(.title3.monospacedDigit())
                .foregroundStyle(.primary)
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
            Text(code ?? String(localized: "无效密钥"))
                .font(.title3.monospacedDigit())
                .foregroundStyle(code == nil ? .red : .primary)
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
        guard entry.type != .steam else { return code }
        var result = ""
        for (index, character) in code.enumerated() {
            if index > 0 && index % 3 == 0 { result.append(" ") }
            result.append(character)
        }
        return result
    }
}
