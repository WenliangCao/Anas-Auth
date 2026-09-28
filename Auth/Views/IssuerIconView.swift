import SwiftUI

/// 发行方图标：手动选择的品牌图标 > 按发行方名称匹配 > 首字母圆形头像
struct IssuerIconView: View {
    let issuer: String
    let iconID: String
    var size: CGFloat = 24

    var body: some View {
        if let icon = resolvedIcon {
            BrandIconImage(icon: icon, size: size)
        } else {
            LetterAvatar(name: issuer, size: size)
        }
    }

    private var resolvedIcon: BrandIcon? {
        if !iconID.isEmpty, let icon = BrandIconCatalog.icon(slug: iconID) {
            return icon
        }
        return BrandIconCatalog.match(issuer: issuer)
    }
}

/// 品牌矢量图，按品牌色着色；颜色与背景太接近时退回正文色（如深色模式下的黑色 logo）
struct BrandIconImage: View {
    let icon: BrandIcon
    var size: CGFloat = 24
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(icon.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        guard let value = UInt32(icon.hex, radix: 16) else { return .primary }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let tooDark = colorScheme == .dark && luminance < 0.15
        let tooLight = colorScheme == .light && luminance > 0.85
        return tooDark || tooLight ? .primary : Color(red: red, green: green, blue: blue)
    }
}

/// 无品牌图标时的首字母圆形头像（同 ente 的兜底样式）
struct LetterAvatar: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        if let initial {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay {
                    Text(initial)
                        .font(.system(size: size * 0.6))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
        }
    }

    /// 首个字母或数字（跳过引号等符号）
    private var initial: String? {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() }
    }

    /// 稳定哈希取色：Swift 的 hashValue 每次启动随机，不能用
    private var color: Color {
        var hash: UInt32 = 0
        for scalar in name.lowercased().unicodeScalars {
            hash = hash &* 31 &+ scalar.value
        }
        return Color.avatarPalette[Int(hash % UInt32(Color.avatarPalette.count))]
    }
}
