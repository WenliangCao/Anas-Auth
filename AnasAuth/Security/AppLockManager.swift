import Foundation
import LocalAuthentication

/// Face ID / 触控 ID / 设备密码锁。状态存 UserDefaults，
/// 锁本身不存任何密钥——只是个"进门闸机"。
@Observable
@MainActor
final class AppLockManager {
    static let shared = AppLockManager()

    private let defaultsKey = "appLockEnabled"

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: defaultsKey)
            isLocked = isEnabled
        }
    }

    private(set) var isLocked: Bool

    /// 正在走系统验证面板。面板会让 App 变为 inactive，且要等收起动画放完
    /// （约 1 秒）才回到 active；这段时间隐私遮罩应让位，否则解锁后内容被挡住
    private(set) var isAuthenticating = false

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: defaultsKey)
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    func lock() {
        isAuthenticating = false
        if isEnabled {
            isLocked = true
        }
    }

    func unlock() async {
        guard isEnabled else {
            isLocked = false
            return
        }
        let context = LAContext()
        isAuthenticating = true
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: String(localized: "解锁以查看你的验证码")
            )
            if success {
                isLocked = false
            }
        } catch {
            // 用户取消或验证失败：保持锁定
        }
    }

    /// 回到 active 时由界面调用：验证面板已完全收起
    func authenticationDidEnd() {
        isAuthenticating = false
    }
}
