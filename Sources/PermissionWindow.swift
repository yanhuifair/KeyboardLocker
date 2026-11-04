import AppKit

/// 权限引导窗口。仅在缺少 TCC 权限时出现，授权完成后自动关闭。
final class PermissionWindowController: NSWindowController, NSWindowDelegate {

    private let retryHandler: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")

    private let contentInset: CGFloat = 32

    init(onRetry: @escaping () -> Void) {
        self.retryHandler = onRetry

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 368),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "KeyboardLocker"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.center()

        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI

    private func buildContent() {
        guard let window else { return }

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // 图标
        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: "keyboard.badge.ellipsis",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
        )
        icon.contentTintColor = .controlAccentColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(icon)

        // 标题
        let title = NSTextField(labelWithString: "需要键盘访问权限")
        title.font = .systemFont(ofSize: 19, weight: .semibold)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)

        // 正文
        let body = NSTextField(wrappingLabelWithString:
            "KeyboardLocker 通过系统级事件拦截来屏蔽全部键盘输入。要启用这项能力，需要在系统设置中授予权限。")
        body.font = .systemFont(ofSize: 12.5)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(body)

        // 步骤卡片
        let card = CardView()
        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        let steps = NSTextField(wrappingLabelWithString:
            "1.  点击下方「打开系统设置」\n"
            + "2.  在「隐私与安全性 › 辅助功能」中打开 KeyboardLocker 开关\n"
            + "3.  若列表里没有它，请到「输入监控」中同样打开\n"
            + "4.  回到这里点击「重新检测」")
        steps.font = .systemFont(ofSize: 12)
        steps.textColor = .labelColor
        steps.isEditable = false
        steps.isSelectable = false
        steps.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(steps)

        // 按钮
        let retryButton = NSButton(title: "重新检测", target: self, action: #selector(retry))
        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .large

        let settingsButton = NSButton(title: "打开系统设置", target: self, action: #selector(openSettings))
        settingsButton.bezelStyle = .rounded
        settingsButton.controlSize = .large
        settingsButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [retryButton, settingsButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(buttonRow)

        // 状态
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.stringValue = "等待授权…"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 34),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: contentInset),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -contentInset),

            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: contentInset + 6),
            body.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -contentInset - 6),

            card.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 18),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: contentInset),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -contentInset),

            steps.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            steps.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            steps.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            steps.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13),

            buttonRow.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 20),
            buttonRow.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            statusLabel.topAnchor.constraint(equalTo: buttonRow.bottomAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18),
        ])

        window.contentView = container
    }

    // MARK: - 行为

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func markGranted() {
        statusLabel.stringValue = "已获得权限 ✓"
        statusLabel.textColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.close()
        }
    }

    @objc private func openSettings() {
        Permissions.requestAccessibilityPrompt()
        Permissions.requestInputMonitoring()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            Permissions.openAccessibilitySettings()
        }
    }

    @objc private func retry() {
        retryHandler()
    }
}

/// 带描边的圆角卡片容器，颜色跟随明暗外观刷新。
private final class CardView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        refreshColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    private func refreshColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        }
    }
}
