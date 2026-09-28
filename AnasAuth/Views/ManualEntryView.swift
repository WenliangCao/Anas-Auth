import SwiftUI
import SwiftData

/// 手动输入密钥的表单。保存前校验 Base32 密钥有效性。
struct ManualEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var issuer = ""
    @State private var accountName = ""
    @State private var secret = ""
    @State private var type: OTPType = .totp
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = OTPGenerator.defaultDigits
    @State private var period = OTPGenerator.defaultPeriod
    @State private var counter = 0

    private var sanitizedSecret: String {
        OTPAuthURLParser.sanitizeSecret(secret)
    }

    private var isSecretValid: Bool {
        !sanitizedSecret.isEmpty && (try? Base32.decode(sanitizedSecret)) != nil
    }

    private var canSave: Bool {
        isSecretValid && (!issuer.isEmpty || !accountName.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账号信息") {
                    TextField("发行方（如 GitHub）", text: $issuer)
                    TextField("账号名（如邮箱）", text: $accountName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Base32 密钥", text: $secret)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    if !secret.isEmpty && !isSecretValid {
                        Text("密钥不是有效的 Base32 编码")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("密钥")
                } footer: {
                    Text("通常在开启两步验证的页面可以找到，形如 JBSW Y3DP EHPK 3PXP")
                }

                Section("参数") {
                    Picker("类型", selection: $type) {
                        Text("基于时间 (TOTP)").tag(OTPType.totp)
                        Text("基于计数器 (HOTP)").tag(OTPType.hotp)
                        Text("Steam").tag(OTPType.steam)
                    }
                    if type != .steam {
                        Picker("算法", selection: $algorithm) {
                            ForEach(OTPAlgorithm.allCases, id: \.self) { algorithm in
                                Text(algorithm.displayName).tag(algorithm)
                            }
                        }
                        Picker("位数", selection: $digits) {
                            Text("6 位").tag(6)
                            Text("7 位").tag(7)
                            Text("8 位").tag(8)
                        }
                        if type == .totp {
                            Stepper("周期：\(period) 秒", value: $period, in: 5...300, step: 5)
                        } else {
                            Stepper("初始计数：\(counter)", value: $counter, in: 0...9999)
                        }
                    }
                }
            }
            .navigationTitle("手动添加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: type) { _, newType in
                if newType == .steam {
                    digits = OTPGenerator.steamDigits
                } else if digits == OTPGenerator.steamDigits {
                    digits = OTPGenerator.defaultDigits
                }
            }
        }
    }

    private func save() {
        let code = OTPCode(
            issuer: issuer.trimmingCharacters(in: .whitespaces),
            accountName: accountName.trimmingCharacters(in: .whitespaces),
            secret: sanitizedSecret,
            algorithm: type == .steam ? .sha1 : algorithm,
            digits: type == .steam ? OTPGenerator.steamDigits : digits,
            period: type == .totp ? period : OTPGenerator.defaultPeriod,
            counter: type == .hotp ? counter : 0,
            type: type
        )
        modelContext.insert(CodeEntry(code: code))
        dismiss()
    }
}
