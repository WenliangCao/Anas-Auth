import SwiftUI

/// 首页顶部的标签筛选条（对齐 ente）：「全部」+ 各标签，横向滚动。
/// 再次点选中的标签会取消筛选，回到「全部」。
struct TagFilterBar: View {
    let tags: [String]
    @Binding var selectedTag: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                TagChip(title: "全部", isSelected: selectedTag == nil) {
                    selectedTag = nil
                }
                ForEach(tags, id: \.self) { tag in
                    TagChip(title: tag, isSelected: selectedTag == tag) {
                        selectedTag = selectedTag == tag ? nil : tag
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
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
        Button(action: action) {
            Text(title)
                .font(.body)
                .lineLimit(1)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.entePurple : Color.tagChipUnselected, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.entePurple.opacity(isSelected ? 0 : 0.2))
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
