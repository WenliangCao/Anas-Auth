import SwiftUI
import SwiftData

/// 编辑已有条目。改动先落在本地副本，点"完成"才一次性写回 SwiftData：
/// - 输入过程中不触发 CloudKit 同步，避免产生大量中间记录
/// - 支持随手取消（下滑或取消按钮），库保持原样
struct EditCodeView: View {
    @Bindable var entry: CodeEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // 本地编辑副本
    @State private var issuer = ""
    @State private var accountName = ""
    @State private var note = ""
    @State private var pinned = false
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var algorithm: OTPAlgorithm = .sha1
    @State private var digits = OTPGenerator.defaultDigits
    @State private var period = OTPGenerator.defaultPeriod

    var body: some View {
        NavigationStack {
            Form {
                Section("账号信息") {
                    TextField("发行方", text: $issuer)
                    TextField("账号名", text: $accountName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("备注") {
                    TextField("备注（可选）", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                    Toggle("置顶", isOn: $pinned)
                }

                Section("标签") {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                    }
                    .onDelete { tags.remove(atOffsets: $0) }
                    TextField("添加标签", text: $newTag)
                        .submitLabel(.done)
                        .onSubmit(addTag)
                }

                if entry.type != .steam {
                    Section("参数") {
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
                        if entry.type == .totp {
                            Stepper("周期：\(period) 秒", value: $period, in: 5...300, step: 5)
                        }
                    }
                }
            }
            .navigationTitle("编辑")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // 从库中的模型拷贝出编辑副本
                issuer = entry.issuer
                accountName = entry.accountName
                note = entry.note
                pinned = entry.pinned
                tags = entry.tags
                algorithm = entry.algorithm
                digits = entry.digits
                period = entry.period
            }
        }
    }

    /// 去掉首尾空格，忽略空值与重复
    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        newTag = ""
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
    }

    private func save() {
        entry.issuer = issuer.trimmingCharacters(in: .whitespaces)
        entry.accountName = accountName.trimmingCharacters(in: .whitespaces)
        entry.note = note
        entry.pinned = pinned
        addTag()
        entry.tags = tags
        entry.algorithm = algorithm
        entry.digits = digits
        entry.period = period
        try? modelContext.save()
    }
}
