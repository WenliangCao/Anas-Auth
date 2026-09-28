import SwiftUI
import UIKit

/// 对齐 ente auth 的配色（取自其 theme/colors.dart 与 ente_theme_data.dart）
extension Color {
    /// 主紫色：进度条、选中态标签
    static let entePurple = Color(red: 0x72 / 255, green: 0x2E / 255, blue: 0xD1 / 255)

    /// 验证码卡片背景
    static let codeCardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 40 / 255, green: 40 / 255, blue: 40 / 255, alpha: 0.6)
            : UIColor(red: 246 / 255, green: 246 / 255, blue: 246 / 255, alpha: 1)
    })

    /// 置顶卡片右上角三角底色
    static let pinnedCorner = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x39 / 255, green: 0x0C / 255, blue: 0x4F / 255, alpha: 1)
            : UIColor(red: 0xF9 / 255, green: 0xEC / 255, blue: 0xFF / 255, alpha: 1)
    })

    /// 无品牌图标时首字母头像的底色
    static let avatarPalette: [Color] = [
        (118, 84, 154), (223, 120, 97), (148, 180, 159), (135, 162, 251),
        (198, 137, 198), (50, 82, 136), (133, 180, 224), (193, 163, 163),
        (66, 97, 101), (221, 157, 226), (130, 171, 139), (155, 187, 232),
        (143, 190, 190), (138, 195, 161), (168, 176, 242), (176, 198, 149),
        (233, 154, 173), (209, 132, 132), (120, 181, 167),
    ].map { Color(red: Double($0.0) / 255, green: Double($0.1) / 255, blue: Double($0.2) / 255) }
}
