import CoreGraphics
import Foundation

/// 基于 CGEventTap 的键盘锁定引擎。
///
/// 设计要点：
/// - tap 在应用启动后常驻于独立线程的 runloop，只有 `isLocked` 为 true 时才吞掉事件。
///   这样「锁 / 解锁」只是一次标志位翻转，没有创建/销毁 tap 的延迟和失败风险。
/// - tap 位于 `.cghidEventTap` 最底层 + `.headInsertEventTap` 最前位置，
///   因此系统快捷键（⌘Tab、⌘Q、⌘⌥⎋ 等）同样会被拦下。
/// - 进程退出后 tap 自动失效，键盘立刻恢复 —— 这是最关键的兜底。
final class KeyboardLockEngine {

    /// tap 被系统因超时禁用后，允许的最大连续重建次数，避免死循环。
    private static let maxReenableAttempts = 5

    private let stateLock = NSLock()

    private var _isLocked = false
    private var _blockedEventCount = 0
    private var reenableAttempts = 0

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    // MARK: - 状态

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return tap != nil
    }

    /// 注意：该属性会在 event tap 回调线程被高频读取，必须加锁。
    var isLocked: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _isLocked
    }

    func setLocked(_ locked: Bool) {
        stateLock.lock()
        _isLocked = locked
        stateLock.unlock()
    }

    /// 已拦截的事件数量（自检用）。
    var blockedEventCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _blockedEventCount
    }

    // MARK: - 生命周期

    /// 创建并启动 event tap。返回 false 通常意味着缺少「辅助功能 / 输入监控」权限。
    @discardableResult
    func start() -> Bool {
        stateLock.lock()
        let alreadyRunning = (tap != nil)
        stateLock.unlock()
        if alreadyRunning { return true }

        // 键盘按下 / 抬起 / 修饰键 / 媒体键（音量、亮度等，rawValue 14 = NX_SYSDEFINED）
        var eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        if let systemDefined = CGEventType(rawValue: 14) {
            eventTypes.append(systemDefined)
        }
        let mask: CGEventMask = eventTypes.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: KeyboardLockEngine.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)

        stateLock.lock()
        tap = port
        runLoopSource = source
        reenableAttempts = 0
        stateLock.unlock()

        let thread = Thread { [weak self] in
            guard let self else { return }
            let runLoop = CFRunLoopGetCurrent()
            self.stateLock.lock()
            self.tapRunLoop = runLoop
            self.stateLock.unlock()

            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()

            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        thread.name = "com.fair.keyboardlocker.event-tap"
        thread.qualityOfService = .userInteractive
        thread.stackSize = 512 * 1024
        thread.start()

        stateLock.lock()
        tapThread = thread
        stateLock.unlock()

        return true
    }

    func stop() {
        stateLock.lock()
        let port = tap
        let runLoop = tapRunLoop
        tap = nil
        tapRunLoop = nil
        runLoopSource = nil
        tapThread = nil
        _isLocked = false
        stateLock.unlock()

        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
    }

    deinit {
        stop()
    }

    // MARK: - 内部

    /// 从任意线程安全地重新启用 tap（系统超时禁用后需要）。
    fileprivate func reenableAfterSystemDisable() {
        stateLock.lock()
        let port = tap
        let attempts = reenableAttempts
        reenableAttempts = attempts + 1
        stateLock.unlock()

        guard let port else { return }
        guard attempts < KeyboardLockEngine.maxReenableAttempts else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    fileprivate func recordBlockedEvent() {
        stateLock.lock()
        _blockedEventCount += 1
        stateLock.unlock()
    }

    /// 定时器重置「连续重建」计数：tap 稳定运行一段时间后，额度回满。
    func resetReenableBudget() {
        stateLock.lock()
        reenableAttempts = 0
        stateLock.unlock()
    }

    // MARK: - 回调

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let engine = Unmanaged<KeyboardLockEngine>.fromOpaque(refcon).takeUnretainedValue()

        // 系统在回调超时 / 用户输入打断时会临时禁用 tap，必须立刻恢复，
        // 否则键盘会在用户毫无察觉的情况下「自动解锁」。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            engine.reenableAfterSystemDisable()
            return Unmanaged.passUnretained(event)
        }

        if engine.isLocked {
            engine.recordBlockedEvent()
            return nil // 吞掉事件 —— 系统与其他应用都收不到
        }

        return Unmanaged.passUnretained(event)
    }
}
