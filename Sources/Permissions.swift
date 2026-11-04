import AppKit
import ApplicationServices

/// 权限相关的检查与引导。
///
/// 拦截键盘事件需要两类 TCC 权限：
/// - 辅助功能（Accessibility）：创建可修改事件的 event tap
/// - 输入监控（Input Monitoring）：读取键盘事件流
/// 实践中两者都可能被要求，所以统一引导用户一并授权。
enum Permissions {

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 弹出系统授权对话框（未授权时）。
    static func requestAccessibilityPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// 请求「输入监控」权限，让应用出现在系统设置的对应列表里。
    static func requestInputMonitoring() {
        if #available(macOS 10.15, *) {
            CGRequestListenEventAccess()
        }
    }

    /// 直接跳到「隐私与安全性 › 辅助功能」。
    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// 直接跳到「隐私与安全性 › 输入监控」。
    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
