import SwiftUI
import SwiftData

/// 编辑已有条目，字段对齐 ente：图标、发行方、密钥、账号、备注、标签。
/// 算法、位数、周期由导入时决定，不允许手动修改。
/// 改动先落在本地副本，点"完成"才一次性写回 SwiftData：
/// - 输入过程中不触发 CloudKit 同步，避免产生大量中间记录
/// - 支持随手取消（下滑或取消按钮），库保持原样
struct EditCodeView: View {
    @Bindable var entry: CodeEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // 本地编辑副本
    @State private var issuer = ""
    @State private var secret = ""
    @State private var accountName = ""
    @State private var note = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var iconID = ""
    @State private var showsSecret = false
    @State private var showingIconPicker = false

    private var sanitizedSecret: String {
        OTPAuthURLParser.sanitizeSecret(secret)
    }

    private var isSecretValid: Bool {
        !sanitizedSecret.isEmpty && (try? Base32.decode(sanitizedSecret)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    iconHeader
                }
                .listRowBackground(Color.clear)

                Section("Issuer") {
                    TextField("Issuer", text: $issuer)
                }

                Section {
                    HStack {
                        Group {
                            if showsSecret {
                                TextField("Secret", text: $secret)
                            } else {
                                SecureField("Secret", text: $secret)
                            }
                        }
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                        Button {
                            showsSecret.toggle()
                        } label: {
                            Image(systemName: showsSecret ? "eye" : "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                        .accessibilityLabel(showsSecret ? "Hide Secret" : "Show Secret")
                    }
                } header: {
                    Text("Secret")
                } footer: {
                    if !isSecretValid {
                        Text(secret.isEmpty ? "The secret can’t be empty" : "The secret isn’t valid Base32 encoding")
                            .foregroundStyle(.red)
                    }
                }

                Section("Account") {
                    TextField("Account", text: $accountName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Note") {
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Tags") {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                    }
                    .onDelete { tags.remove(atOffsets: $0) }
                    TextField("Add Tag", text: $newTag)
                        .submitLabel(.done)
                        .onSubmit(addTag)
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save()
                        dismiss()
                    }
                    .disabled(!isSecretValid)
                }
            }
            .navigationDestination(isPresented: $showingIconPicker) {
                IconPickerView(issuer: issuer, selection: $iconID)
            }
            .onAppear {
                // 从库中的模型拷贝出编辑副本
                guard issuer.isEmpty && secret.isEmpty else { return } // 从图标页返回时不覆盖
                issuer = entry.issuer
                iconID = entry.iconID
                secret = entry.secret
                accountName = entry.accountName
                note = entry.note
                tags = entry.tags
            }
        }
    }

    /// 顶部图标：点击进入图标选择，右下角铅笔提示可编辑
    private var iconHeader: some View {
        Button {
            showingIconPicker = true
        } label: {
            IssuerIconView(issuer: issuer, iconID: iconID, size: 56)
                .frame(width: 88, height: 88)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1.5)
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "pencil")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 30, height: 30)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                        .offset(x: 10, y: 10)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Change Icon")
    }

    /// 去掉首尾空格，忽略空值与重复
    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        newTag = ""
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
    }

    private func save() {
        addTag()
        entry.issuer = issuer.trimmingCharacters(in: .whitespaces)
        entry.secret = sanitizedSecret
        entry.accountName = accountName.trimmingCharacters(in: .whitespaces)
        entry.note = note
        entry.tags = tags
        entry.iconID = iconID
        try? modelContext.save()
    }
}
