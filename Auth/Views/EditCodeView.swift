import SwiftUI
import SwiftData

/// 编辑已有条目。CodeEntry 是 SwiftData @Model，直接改属性即自动保存。
struct EditCodeView: View {
    @Bindable var entry: CodeEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("账号信息") {
                    TextField("发行方", text: $entry.issuer)
                    TextField("账号名", text: $entry.accountName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("备注") {
                    TextField("备注（可选）", text: $entry.note, axis: .vertical)
                        .lineLimit(1...4)
                    Toggle("置顶", isOn: $entry.pinned)
                }

                if entry.type != .steam {
                    Section("参数") {
                        Picker("算法", selection: $entry.algorithm) {
                            ForEach(OTPAlgorithm.allCases, id: \.self) { algorithm in
                                Text(algorithm.displayName).tag(algorithm)
                            }
                        }
                        Picker("位数", selection: $entry.digits) {
                            Text("6 位").tag(6)
                            Text("7 位").tag(7)
                            Text("8 位").tag(8)
                        }
                        if entry.type == .totp {
                            Stepper("周期：\(entry.period) 秒", value: $entry.period, in: 5...300, step: 5)
                        }
                    }
                }
            }
            .navigationTitle("编辑")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
