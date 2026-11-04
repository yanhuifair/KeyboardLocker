import AppKit

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
}

// 菜单栏常驻应用：不进入 Dock，不显示主窗口。
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
