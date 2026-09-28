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
                Section("Account Details") {
                    TextField("Issuer (e.g. GitHub)", text: $issuer)
                    TextField("Account (e.g. email)", text: $accountName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Base32 Secret", text: $secret)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    if !secret.isEmpty && !isSecretValid {
                        Text("The secret isn’t valid Base32 encoding")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Secret")
                } footer: {
                    Text("You can usually find it on the page where you turn on two-factor authentication. It looks like JBSW Y3DP EHPK 3PXP.")
                }

                Section("Parameters") {
                    Picker("Type", selection: $type) {
                        Text("Time-based (TOTP)").tag(OTPType.totp)
                        Text("Counter-based (HOTP)").tag(OTPType.hotp)
                        Text("Steam").tag(OTPType.steam)
                    }
                    if type != .steam {
                        Picker("Algorithm", selection: $algorithm) {
                            ForEach(OTPAlgorithm.allCases, id: \.self) { algorithm in
                                Text(algorithm.displayName).tag(algorithm)
                            }
                        }
                        Picker("Digits", selection: $digits) {
                            Text("6 digits").tag(6)
                            Text("7 digits").tag(7)
                            Text("8 digits").tag(8)
                        }
                        if type == .totp {
                            Stepper("Period: \(period) s", value: $period, in: 5...300, step: 5)
                        } else {
                            Stepper("Initial counter: \(counter)", value: $counter, in: 0...9999)
                        }
                    }
                }
            }
            .navigationTitle("Add Manually")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
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
