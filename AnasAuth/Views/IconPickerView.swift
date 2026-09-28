import SwiftUI

/// 选择品牌图标（对齐 ente 的 Choose icon）：三列网格 + 搜索，图标与 ente 相同。
/// 第一格「默认」表示按发行方名称自动匹配。
struct IconPickerView: View {
    let issuer: String
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    private var icons: [BrandIcon] {
        guard !searchText.isEmpty else { return BrandIconCatalog.all }
        let query = BrandIconCatalog.normalize(searchText)
        return BrandIconCatalog.all.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || (!query.isEmpty && $0.id.contains(query))
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                if searchText.isEmpty {
                    cell(title: "默认", isSelected: selection.isEmpty) {
                        IssuerIconView(issuer: issuer, iconID: "", size: 44)
                    } action: {
                        select("")
                    }
                }
                ForEach(icons) { icon in
                    cell(title: icon.title, isSelected: selection == icon.id) {
                        BrandIconImage(icon: icon, size: 44)
                    } action: {
                        select(icon.id)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("选择图标")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索")
        .overlay {
            if icons.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func select(_ slug: String) {
        selection = slug
        dismiss()
    }

    private func cell(
        title: String,
        isSelected: Bool,
        @ViewBuilder icon: () -> some View,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                icon()
                    .frame(height: 44)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
