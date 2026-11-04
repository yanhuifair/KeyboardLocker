import AppKit
import CoreGraphics

/// 命令行自检：验证 event tap 是否真的能吞掉键盘事件。
///
/// 用法：KeyboardLocker.app/Contents/MacOS/KeyboardLocker --selftest
/// 退出码：0 = 通过，1 = 拦截失败，2 = 缺少权限
enum SelfTest {

    static func run() -> Never {
        print("[selftest] 创建键盘事件拦截器…")
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
        print("[selftest] 已切换为锁定状态，注入 20 个模拟按键事件…")

        // KeypadClear 无副作用，避免自检时往焦点窗口里打字
        let clearKey: CGKeyCode = 71
        for _ in 0..<10 {
            CGEvent(keyboardEventSource: nil, virtualKey: clearKey, keyDown: true)?
                .post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: clearKey, keyDown: false)?
                .post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.6)

        let blocked = engine.blockedEventCount
        print("[selftest] 拦截计数: \(blocked) / 20")

        engine.setLocked(false)
        Thread.sleep(forTimeInterval: 0.2)
        engine.stop()

        if blocked >= 20 {
            print("[selftest] PASS — 键盘事件已被完整拦截")
            exit(0)
        } else if blocked > 0 {
            print("[selftest] PARTIAL — 部分事件未被拦截")
            exit(1)
        } else {
            print("[selftest] FAIL — 事件未被拦截")
            exit(1)
        }
    }
}
