import AppKit
import CoreGraphics

/// 命令行自检：验证 event tap 是否真的能吞掉键盘和指针输入，以及解锁快捷键是否可用。
///
/// 用法：KeyboardLocker.app/Contents/MacOS/KeyboardLocker --selftest
/// 退出码：0 = 通过，1 = 拦截或解锁失败，2 = 缺少权限
enum SelfTest {

    static func run() -> Never {
        // 兜底：任何一步卡住都不要把键盘和触控板留在死锁状态
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) {
            print("[selftest] FAIL — 超时，强制释放输入")
            exit(1)
        }

        print("[selftest] 创建输入拦截器…")
        let engine = KeyboardLockEngine()

        guard engine.start() else {
            print("[selftest] FAIL — 无法创建 event tap")
            print("[selftest] 请在「系统设置 › 隐私与安全性 › 辅助功能 / 输入监控」中授权后重试")
            exit(2)
        }
        print("[selftest] OK — event tap 已创建")

        // 等待 tap 线程把 runloop 跑起来
        Thread.sleep(forTimeInterval: 0.8)
        engine.setLocked(true)
        Thread.sleep(forTimeInterval: 0.25)

        var failures: [String] = []

        // MARK: ① 键盘
        print("[selftest] ① 注入 20 个模拟按键…")
        // KeypadClear 无副作用，避免自检时往焦点窗口里打字
        let clearKey: CGKeyCode = 71
        for _ in 0..<10 {
            postKey(clearKey, down: true)
            postKey(clearKey, down: false)
        }
        Thread.sleep(forTimeInterval: 0.6)

        let blockedKeys = engine.blockedEventCount
        print("[selftest]    拦截计数: \(blockedKeys) / 20")
        if blockedKeys < 20 {
            failures.append("按键未全部拦截（\(blockedKeys)/20）")
        }

        // MARK: ② 指针
        print("[selftest] ② 注入一次指针移动…")
        let blockedBeforePointer = engine.blockedEventCount
        let cursorBefore = CGEvent(source: nil)?.location ?? .zero
        let target = CGPoint(x: cursorBefore.x + 240, y: cursorBefore.y + 160)
        if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                              mouseCursorPosition: target, mouseButton: .left) {
            // 硬件事件都带位移量，这里补上，才是和真实触控板等价的输入
            move.setIntegerValueField(.mouseEventDeltaX, value: 240)
            move.setIntegerValueField(.mouseEventDeltaY, value: 160)
            move.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.45)

        let cursorAfter = CGEvent(source: nil)?.location ?? .zero
        let drift = hypot(cursorAfter.x - cursorBefore.x, cursorAfter.y - cursorBefore.y)
        let pointerEvents = engine.blockedEventCount - blockedBeforePointer
        print("[selftest]    指针事件被吞: \(pointerEvents)，光标位移: \(Int(drift)) pt")
        if pointerEvents < 1 {
            failures.append("指针事件没有被 tap 看到")
        }
        if drift > 2 {
            failures.append("光标没有被固定（移动了 \(Int(drift)) pt）")
        }

        // MARK: ③ ⌃⌥⌘⇧L 不应解锁
        print("[selftest] ③ 注入 ⌃⌥⌘⇧L（多按 ⇧，不应解锁）…")
        let withShift = KeyboardLockEngine.unlockFlags.union(.maskShift)
        postFlags(withShift)
        postKey(KeyboardLockEngine.unlockKeyCode, down: true, flags: withShift)
        postKey(KeyboardLockEngine.unlockKeyCode, down: false, flags: withShift)
        Thread.sleep(forTimeInterval: 0.4)

        print("[selftest]    状态: \(engine.isLocked ? "仍锁定" : "被解锁了")")
        if !engine.isLocked {
            failures.append("多按 ⇧ 也能解锁")
        }

        // MARK: ④ ⌃⌥⌘L 解锁
        print("[selftest] ④ 注入 ⌃⌥⌘L…")
        postFlags([.maskControl])
        postFlags([.maskControl, .maskAlternate])
        postFlags(KeyboardLockEngine.unlockFlags)
        postKey(KeyboardLockEngine.unlockKeyCode, down: true,
                flags: KeyboardLockEngine.unlockFlags)
        postKey(KeyboardLockEngine.unlockKeyCode, down: false,
                flags: KeyboardLockEngine.unlockFlags)
        Thread.sleep(forTimeInterval: 0.5)

        print("[selftest]    状态: \(engine.isLocked ? "仍锁定" : "已解锁")")
        if engine.isLocked {
            failures.append("⌃⌥⌘L 没能解锁")
        }

        // MARK: ⑤ 未锁定时按快捷键
        print("[selftest] ⑤ 未锁定状态下再按 ⌃⌥⌘L…")
        let blockedBeforeShortcut = engine.blockedEventCount
        postKey(KeyboardLockEngine.unlockKeyCode, down: true,
                flags: KeyboardLockEngine.unlockFlags)
        postKey(KeyboardLockEngine.unlockKeyCode, down: false,
                flags: KeyboardLockEngine.unlockFlags)
        Thread.sleep(forTimeInterval: 0.3)

        let shortcutEvents = engine.blockedEventCount - blockedBeforeShortcut
        print("[selftest]    触发键被吞: \(shortcutEvents)")
        if shortcutEvents < 1 {
            failures.append("未锁定时按快捷键没有被捕获")
        }

        // MARK: 收尾
        engine.setLocked(false)
        Thread.sleep(forTimeInterval: 0.15)

        // 如果指针没被拦住，把光标放回原处
        if drift > 2,
           let restore = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                 mouseCursorPosition: cursorBefore, mouseButton: .left) {
            restore.post(tap: .cghidEventTap)
        }

        let reenables = engine.reenableCount
        print("[selftest] tap 被系统重建: \(reenables) 次")
        if reenables > 0 {
            failures.append("tap 被系统禁用了 \(reenables) 次，锁定期间可能短暂漏事件")
        }
        engine.stop()

        if failures.isEmpty {
            print("[selftest] PASS — 键盘与指针已锁定，⌃⌥⌘L 可切换锁 / 解锁")
            exit(0)
        } else {
            for failure in failures {
                print("[selftest] FAIL — \(failure)")
            }
            exit(1)
        }
    }

    // MARK: - 注入辅助

    private static func postKey(_ code: CGKeyCode, down: Bool,
                                flags: CGEventFlags = []) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code,
                                  keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private static func postFlags(_ flags: CGEventFlags) {
        guard let event = CGEvent(source: nil) else { return }
        event.type = .flagsChanged
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}
