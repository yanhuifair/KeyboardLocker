import CoreGraphics
import Foundation

/// 基于 CGEventTap 的输入锁定引擎。
///
/// 设计要点：
/// - tap 在应用启动后常驻于独立线程的 runloop，只有 `isLocked` 为 true 时才吞掉事件。
///   这样「锁 / 解锁」只是一次标志位翻转，没有创建/销毁 tap 的延迟和失败风险。
/// - tap 位于 `.cghidEventTap` 最底层 + `.headInsertEventTap` 最前位置，
///   因此系统快捷键（⌘Tab、⌘Q、⌘⌥⎋ 等）同样会被拦下。
/// - 键盘和指针一起拦：光标移动、点击、拖拽、滚轮全部吞掉，擦触控板时不会把光标甩出去、
///   也不会误点到别的窗口。代价是锁定期间菜单栏图标点不动，所以必须留一条纯键盘的出路。
/// - 快捷键在吞事件之前判定：⌃⌥⌘L 是锁 / 解锁的总开关，未锁定按下就上锁，锁定按下就解锁。
///   锁定期间菜单栏图标点不动，所以它也是唯一的解锁出路。
/// - 进程退出后 tap 自动失效，输入立刻恢复 —— 这是最关键的兜底。
final class KeyboardLockEngine {

    /// tap 被系统因超时禁用后，允许的最大连续重建次数，避免死循环。
    private static let maxReenableAttempts = 5

    /// 锁定期间一并吞掉的指针事件（触控板 / 鼠标 / 数位板指针）。
    private static let pointerTypes: [CGEventType] = [
        .mouseMoved,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        .scrollWheel,
        .tabletPointer,
    ]

    /// 会改变光标位置的事件。吞掉它们只能阻止应用收到事件，
    /// 光标本身是由窗口服务器先移动再交给 tap 的，所以还得把位置掰回去。
    private static let pointerMoveTypes: Set<CGEventType> = [
        .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]

    /// 触控板手势事件（捏合、旋转、轻扫、手势开始/结束）。
    /// 这些在 CGEventType 里没有正式名字，只能按 NX 事件编号 29…33 取。
    private static let gestureTypes: [CGEventType] = (29...33).compactMap {
        CGEventType(rawValue: CGEventType.RawValue($0))
    }

    /// ⌃⌥⌘ + L：锁 / 解锁总开关。用物理键位 37（ANSI L），与键盘布局无关。
    /// 严格匹配：多按 Shift 不算，避免和 ⌃⌥⌘⇧L 这类系统快捷键撞车。
    static let unlockKeyCode: CGKeyCode = 37
    static let unlockFlags: CGEventFlags = [
        .maskControl, .maskAlternate, .maskCommand,
    ]

    /// 参与严格比对的修饰键。Caps Lock、fn 不在其中，开着 Caps Lock 也能用。
    static let shortcutModifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand,
    ]

    private let stateLock = NSLock()

    private var _isLocked = false
    private var _blockedEventCount = 0
    private var reenableAttempts = 0

    /// 最近一次 flagsChanged 带来的修饰键状态。锁定期间 flagsChanged 会被吞掉，
    /// 但 tap 依然能看到事件本身，所以这里自己记一份，避免依赖 keyDown 的 flags。
    private var trackedModifiers: CGEventFlags = []

    /// 锁定瞬间的光标位置。锁定期间指针事件全部丢弃，光标再被掰回这里。
    ///
    /// 不用 CGAssociateMouseAndMouseCursorPosition(0) 冻结指针：那是窗口服务器的全局状态，
    /// 进程异常退出后光标会留在冻住的状态，属于比锁键盘更糟的故障。
    private var pinnedCursor: CGPoint?

    /// Warp 之后的静默期，用来吃掉 Warp 自己产生的那个事件。
    private static let warpQuietInterval: CFAbsoluteTime = 0.05
    private var warpSuppressUntil: CFAbsoluteTime = 0

    /// 参数是按下快捷键后的目标状态：true = 上锁，false = 解锁。
    private var shortcutHandler: ((Bool) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    /// 快捷键触发时回调（主线程），由 AppDelegate 应用目标状态并同步菜单栏图标。
    var onShortcut: ((Bool) -> Void)? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return shortcutHandler
        }
        set {
            stateLock.lock()
            shortcutHandler = newValue
            stateLock.unlock()
        }
    }

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
        if locked {
            // 上锁时清掉旧的修饰键快照：点图标那一刻按着 ⌘ 之类的残留不能让 L 一按就解锁
            trackedModifiers = []
            pinnedCursor = CGEvent(source: nil)?.location
            warpSuppressUntil = 0
        } else {
            pinnedCursor = nil
            warpSuppressUntil = 0
        }
        stateLock.unlock()
    }

    /// 已拦截的输入事件数量（自检用）。
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

        // 键盘按下 / 抬起 / 修饰键 / 媒体键（rawValue 14 = NX_SYSDEFINED）
        var eventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        if let systemDefined = CGEventType(rawValue: 14) {
            eventTypes.append(systemDefined)
        }
        eventTypes.append(contentsOf: Self.pointerTypes)
        eventTypes.append(contentsOf: Self.gestureTypes)

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
        trackedModifiers = []
        pinnedCursor = nil
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

    fileprivate func updateTrackedModifiers(_ flags: CGEventFlags) {
        let relevant: CGEventFlags = [
            .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
        ]
        stateLock.lock()
        trackedModifiers = flags.intersection(relevant)
        stateLock.unlock()
    }

    /// 把光标掰回锁定时的位置（tap 线程）。
    ///
    /// 事件已经被丢弃，但光标早在事件进入 tap 之前就被窗口服务器移动了，
    /// 所以擦触控板时光标仍会滑走。这里每次移动都 Warp 回去，屏幕上看着就是钉住的。
    /// Warp 不发事件给应用，也不改变任何全局状态，进程退出即失效。
    fileprivate func pinCursorIfNeeded(type: CGEventType, event: CGEvent) {
        guard Self.pointerMoveTypes.contains(type) else { return }

        stateLock.lock()
        let anchor = pinnedCursor
        let suppressUntil = warpSuppressUntil
        stateLock.unlock()
        guard let anchor else { return }

        // Warp 自身也会产生事件。给它留一小段静默期，
        // 否则「Warp → 新事件 → 又 Warp」会变成每秒两百次的空转。
        let now = CFAbsoluteTimeGetCurrent()
        guard now >= suppressUntil else { return }

        // 真实移动一定带位移量；Warp 自己产生的事件位移是 0。
        // 这是断掉「Warp → 新事件 → 又 Warp」连锁的关键判据。
        let dx = event.getIntegerValueField(.mouseEventDeltaX)
        let dy = event.getIntegerValueField(.mouseEventDeltaY)
        guard dx != 0 || dy != 0 else { return }

        let location = event.location
        guard abs(location.x - anchor.x) > 0.5 || abs(location.y - anchor.y) > 0.5 else { return }

        stateLock.lock()
        warpSuppressUntil = now + Self.warpQuietInterval
        stateLock.unlock()
        CGWarpMouseCursorPosition(anchor)
    }

    /// 系统强制重建 tap 的次数（自检用）。
    var reenableCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return reenableAttempts
    }

    private var currentModifiers: CGEventFlags {
        stateLock.lock()
        defer { stateLock.unlock() }
        return trackedModifiers
    }

    /// 定时器重置「连续重建」计数：tap 稳定运行一段时间后，额度回满。
    func resetReenableBudget() {
        stateLock.lock()
        reenableAttempts = 0
        stateLock.unlock()
    }

    // MARK: - 快捷键

    /// 判断并触发 ⌃⌥⌘L。返回 true 表示命中了快捷键，调用方要把这个按键吞掉。
    ///
    /// 解锁方向上先就地放开拦截（不然随后的 keyUp 也会被吞），再交给主线程同步 UI；
    /// 上锁方向则完全交给主线程的 `applyLocked`，这样锁屏保护等判断都能复用。
    fileprivate func handleShortcut(type: CGEventType, event: CGEvent) -> Bool {
        guard type == .keyDown,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0
        else { return false }

        let keyCode = CGKeyCode(
            truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)
        )
        guard keyCode == Self.unlockKeyCode else { return false }

        // 严格相等而不是「包含」：多按 ⇧ 不应触发
        let flags = event.flags.union(currentModifiers)
            .intersection(Self.shortcutModifiers)
        guard flags == Self.unlockFlags else { return false }

        let shouldLock = !isLocked
        if !shouldLock {
            setLocked(false) // 立即生效，不等主线程跑完
        }

        stateLock.lock()
        let handler = shortcutHandler
        stateLock.unlock()

        if let handler {
            DispatchQueue.main.async { handler(shouldLock) }
        }
        return true
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

        // 修饰键状态要在吞事件之前记下来，快捷键靠它判断
        if type == .flagsChanged {
            engine.updateTrackedModifiers(event.flags)
        }

        // 快捷键在任何状态下都先判定：未锁定按下就上锁，锁定按下就解锁。
        // 命中的按键一律吞掉，避免把 L 打进当前应用。
        if engine.handleShortcut(type: type, event: event) {
            engine.recordBlockedEvent()
            return nil
        }

        guard engine.isLocked else {
            return Unmanaged.passUnretained(event)
        }

        engine.pinCursorIfNeeded(type: type, event: event)
        engine.recordBlockedEvent()
        return nil
    }
}
