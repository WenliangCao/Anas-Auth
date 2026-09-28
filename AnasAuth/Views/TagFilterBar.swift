import SwiftUI

/// 首页顶部的标签筛选条（对齐 ente）：「全部」+ 各标签，横向滚动。
/// 用原生 Liquid Glass 按钮，不加强调色；选中的标签用突出样式。
/// 再次点选中的标签会取消筛选，回到「全部」。
struct TagFilterBar: View {
    let tags: [String]
    @Binding var selectedTag: String?

    var body: some View {
        ScrollView(.horizontal) {
            GlassContainer {
                HStack(spacing: 8) {
                    TagChip(title: String(localized: "All"), isSelected: selectedTag == nil) {
                        selectedTag = nil
                    }
                    ForEach(tags, id: \.self) { tag in
                        TagChip(title: tag, isSelected: selectedTag == tag) {
                            selectedTag = selectedTag == tag ? nil : tag
                        }
                    }
                }
                .padding(.horizontal, 16)
                // 给玻璃的阴影留出空间，避免被滚动视图裁掉
                .padding(.vertical, 6)
            }
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selectedTag)
    }
}

private struct TagChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            Button(title, action: action)
                .glassProminentButtonStyle()
                .buttonBorderShape(.capsule)
                .tint(.primary)
                .foregroundStyle(Color(.systemBackground))
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(title, action: action)
                .glassButtonStyle()
                .buttonBorderShape(.capsule)
                .foregroundStyle(.primary)
        }
    }
}
