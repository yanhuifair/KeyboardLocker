import AppKit

/// 菜单栏常驻的键盘锁。
///
/// 交互只有两件事：点图标切换锁定状态，右键菜单里退出。
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let engine = KeyboardLockEngine()
    private let icon = StatusIconController()

    private var statusItem: NSStatusItem!
    private var contextMenu: NSMenu!
    private lazy var permissionWindow = PermissionWindowController { [weak self] in
        self?.retryPermission()
    }
    private var permissionPollTimer: Timer?
    private var screenLockWatchTimer: Timer?

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        buildMenu()
        registerSystemObservers()

        if !engine.start() {
            startPermissionPolling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.permissionWindow.present()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 双保险：任何情况下都不把键盘留在锁死状态
        engine.setLocked(false)
        engine.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        permissionWindow.present()
        return true
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        icon.attach(to: button)
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isSecondary {
            showContextMenu()
        } else {
            toggleLock()
        }
    }

    private func showContextMenu() {
        refreshMenu()
        statusItem.menu = contextMenu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === contextMenu else { return }
        refreshMenu()
    }

    // MARK: - 锁定

    private func toggleLock() {
        guard ensureEngineReady() else { return }

        let target = !engine.isLocked
        // 屏幕已经锁着的时候不允许上锁：那时用户唯一需要的就是键盘能打密码
        if target && Self.isScreenLocked() { return }
        applyLocked(target)
    }

    private func applyLocked(_ locked: Bool) {
        engine.setLocked(locked)
        icon.setLocked(locked)
        if locked {
            engine.resetReenableBudget()
            startScreenLockWatch()
        } else {
            stopScreenLockWatch()
            releaseStuckModifiers()
        }
        refreshMenu()
    }

    /// 解锁后把残留的修饰键状态清掉。
    ///
    /// 锁定那一刻如果正按着 ⌘ / ⇧ / ⌥ / ⌃，随后的 keyUp 会被拦掉，
    /// 系统就一直以为它被按住，解锁后会出现「键盘像被卡住」的错觉。
    /// 这里在解锁后补发一次松开，让状态归位。
    ///
    /// 不处理 Caps Lock —— 它是开关而非按住，强制清零反而会关掉用户开着的状态。
    private func releaseStuckModifiers() {
        let modifierKeyCodes: [CGKeyCode] = [
            54, 55, // 右 ⌘ / 左 ⌘
            56, 60, // 左 ⇧ / 右 ⇧
            58, 61, // 左 ⌥ / 右 ⌥
            59, 62, // 左 ⌃ / 右 ⌃
            63,     // fn
        ]

        // 先广播一个空 flags，再逐个补 keyUp，覆盖两种修饰键状态来源
        if let flagsEvent = CGEvent(source: nil) {
            flagsEvent.type = .flagsChanged
            flagsEvent.flags = []
            flagsEvent.post(tap: .cghidEventTap)
        }

        for keyCode in modifierKeyCodes {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
                continue
            }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    /// 确保 event tap 已经在运行；失败时引导授权。
    private func ensureEngineReady() -> Bool {
        if engine.isRunning { return true }
        if engine.start() {
            stopPermissionPolling()
            permissionWindow.markGranted()
            return true
        }
        startPermissionPolling()
        permissionWindow.present()
        return false
    }

    private func retryPermission() {
        if engine.isRunning {
            permissionWindow.markGranted()
            return
        }
        if engine.start() {
            stopPermissionPolling()
            permissionWindow.markGranted()
        }
    }

    // MARK: - 权限轮询

    private func startPermissionPolling() {
        guard permissionPollTimer == nil else { return }
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.engine.isRunning {
                self.stopPermissionPolling()
                return
            }
            if self.engine.start() {
                self.stopPermissionPolling()
                self.permissionWindow.markGranted()
                self.refreshMenu()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionPollTimer = timer
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    // MARK: - 系统事件

    private func registerSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(handleSleepOrScreenLock),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSleepOrScreenLock),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        // 屏幕锁定后必须能用键盘输入密码，绝不能让用户被挡在外面
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSleepOrScreenLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
    }

    @objc private func handleSleepOrScreenLock() {
        guard engine.isLocked else { return }
        applyLocked(false)
    }

    // MARK: - 锁屏兜底

    /// 锁屏后键盘必须立刻恢复，否则用户打不了登录密码。
    ///
    /// 通知是即时的第一道，但分布式通知存在收不到的可能（系统更新、通知被限流），
    /// 所以锁定期间再每秒查一次会话状态做兜底 —— 最坏 1 秒内一定会解锁。
    private func startScreenLockWatch() {
        guard screenLockWatchTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.engine.isLocked else { return }
            if Self.isScreenLocked() {
                self.applyLocked(false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        screenLockWatchTimer = timer
    }

    private func stopScreenLockWatch() {
        screenLockWatchTimer?.invalidate()
        screenLockWatchTimer = nil
    }

    private static func isScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let value = session["CGSSessionScreenIsLocked"]
        else { return false }

        // 未锁屏时这个键通常直接不存在；锁屏时可能是 Bool 也可能是 NSNumber
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    @objc private func handleSystemWake() {
        engine.resetReenableBudget()
        if !engine.isRunning {
            _ = ensureEngineReady()
        }
    }

    // MARK: - 菜单内容

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let toggleItem = NSMenuItem(
            title: "锁定键盘",
            action: #selector(menuToggleLock),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        contextMenu = menu
    }

    private func refreshMenu() {
        contextMenu?.items.first?.title = engine.isLocked ? "解锁键盘" : "锁定键盘"
    }

    @objc private func menuToggleLock() {
        toggleLock()
    }
}
