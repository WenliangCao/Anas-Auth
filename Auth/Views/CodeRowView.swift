import SwiftUI

struct CodeRowView: View {
    let entry: CodeEntry

    var body: some View {
        if entry.type == .hotp {
            HStack {
                infoStack(code: currentCodeText(at: .now))
                Spacer()
                Image(systemName: "number.circle")
                    .foregroundStyle(.secondary)
            }
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    infoStack(code: currentCodeText(at: context.date))
                    Spacer()
                    countdownView(at: context.date)
                }
            }
        }
    }

    private func infoStack(code: String?) -> some View {
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
            if let code {
                Text(code)
                    .font(.title3.monospacedDigit())
            } else {
                Text("无效密钥")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
        }
    }

    private func countdownView(at date: Date) -> some View {
        let remaining = OTPGenerator.remainingSeconds(at: date, period: entry.period)
        return ZStack {
            ProgressView(value: Double(remaining), total: Double(max(entry.period, 1)))
                .progressViewStyle(.circular)
                .tint(remaining <= 5 ? .red : .accentColor)
            Text("\(remaining)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 44, height: 44)
    }

    /// 当前验证码，格式化为每 3 位一组，便于阅读
    func currentCodeText(at date: Date) -> String? {
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
