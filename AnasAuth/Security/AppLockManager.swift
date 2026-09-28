import LocalAuthentication
import UIKit

/// Face ID / 触控 ID / 设备密码锁。状态存 UserDefaults，
/// 锁本身不存任何密钥——只是个"进门闸机"。
@Observable
@MainActor
final class AppLockManager {
    static let shared = AppLockManager()

    private let defaultsKey = "appLockEnabled"

    private(set) var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: defaultsKey) }
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

    /// 设备设了锁屏密码才能用 App 锁；否则系统验证必然失败，开了会把用户锁在外面
    static var isDevicePasscodeSet: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// 开启前先验证一次机主身份；验证通过才开启，但不立即上锁（切到后台时才锁）
    func enable() async {
        guard !isEnabled,
              await authenticate(reason: String(localized: "Verify your identity to turn on App Lock")) else { return }
        isEnabled = true
    }

    func disable() {
        isEnabled = false
        isLocked = false
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
        var error: NSError?
        if !LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error),
           error?.code == LAError.passcodeNotSet.rawValue {
            // 开锁后用户关掉了设备密码：已无从验证，放行而不是永久锁死
            isLocked = false
            return
        }
        if await authenticate(reason: String(localized: "Unlock to view your codes")) {
            isLocked = false
        }
    }

    /// 回到 active 时由界面调用：验证面板已完全收起
    func authenticationDidEnd() {
        isAuthenticating = false
    }

    /// 弹系统验证面板；正在验证时不重复弹（如自动解锁与点按钮同时触发）
    private func authenticate(reason: String) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer {
            // 面板没弹出就失败时 App 一直是 active，收不到"回到 active"，要在这里复位
            if UIApplication.shared.applicationState == .active {
                isAuthenticating = false
            }
        }
        do {
            return try await LAContext().evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            // 用户取消或验证失败
            return false
        }
    }
}
