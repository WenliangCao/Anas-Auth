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

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: defaultsKey)
        self.isEnabled = enabled
        self.isLocked = enabled
    }

    func lock() {
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
}
