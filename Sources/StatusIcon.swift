import AppKit

/// 菜单栏图标的状态与切换动效。
///
/// 未锁定：`keyboard` 线框符号，作为 template 跟随菜单栏主题色。
/// 已锁定：`keyboard.fill` + `lock.fill` 合成的红色图标，语义一眼可辨。
final class StatusIconController {

    private weak var button: NSStatusBarButton?
    private(set) var isLocked = false

    // MARK: - 挂载

    func attach(to button: NSStatusBarButton) {
        self.button = button
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.alphaValue = 1
        applyAppearance()
    }

    // MARK: - 状态切换

    /// 切换图标。
    ///
    /// 这里刻意不做 alpha 过渡动画：`NSStatusBarButton` 不参与 `NSAnimationContext`
    /// 的属性动画，`animator().alphaValue` 会被丢弃、按钮就停在中间透明度上，
    /// 在彩色壁纸的菜单栏里几乎看不见。状态本身的变化（线框 → 实心红 + 锁）
    /// 已经足够醒目。
    func setLocked(_ locked: Bool) {
        isLocked = locked
        applyAppearance()
        guard let button else { return }
        button.alphaValue = 1
        button.needsDisplay = true
        button.superview?.needsDisplay = true
    }

    // MARK: - 绘制

    private func applyAppearance() {
        guard let button else { return }
        if isLocked {
            button.image = StatusIcon.lockedIcon()
            button.toolTip = "键盘已锁定 · 点击解锁"
            button.setAccessibilityLabel("键盘已锁定")
        } else {
            button.image = StatusIcon.idleIcon()
            button.toolTip = "KeyboardLocker · 点击锁定键盘"
            button.setAccessibilityLabel("键盘未锁定")
            button.alphaValue = 1
        }
    }
}

// MARK: - 图标生成

enum StatusIcon {

    /// 两种状态共用同一块画布。尺寸只要差哪怕 1 点，
    /// `NSStatusItem` 在二次切换时就会把按钮宽度重算错，图标直接消失。
    private static let canvas = NSSize(width: 28, height: 17)

    static func idleIcon() -> NSImage? {
        guard let symbol = symbol("keyboard", pointSize: 17, weight: .regular) else { return nil }
        let image = NSImage(size: canvas, flipped: false) { _ in
            let size = symbol.size
            symbol.draw(in: NSRect(
                x: (canvas.width - size.width) / 2,
                y: (canvas.height - size.height) / 2,
                width: size.width,
                height: size.height
            ))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 锁定态：同一个键盘符号，实心 + 系统红。
    ///
    /// 颜色必须「烧」进位图再交给按钮：直接给一个带 palette 的 SF Symbol，
    /// 菜单栏会按符号自己的 template 规则重新渲染，红色会退回成白色。
    static func lockedIcon() -> NSImage? {
        guard let symbol = symbol("keyboard.fill", pointSize: 17, weight: .regular) else { return nil }
        let mask = NSImage(size: canvas, flipped: false) { _ in
            let size = symbol.size
            symbol.draw(in: NSRect(
                x: (canvas.width - size.width) / 2,
                y: (canvas.height - size.height) / 2,
                width: size.width,
                height: size.height
            ))
            return true
        }
        return tinted(mask, with: .systemRed)
    }

    // MARK: - Helpers

    private static func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        return base.withSymbolConfiguration(configuration)
    }

    /// 用 CoreGraphics 把蒙版整体染成指定颜色（2x 位图，`.sourceIn` 混合）。
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage? {
        let pointSize = image.size
        guard pointSize.width > 0, pointSize.height > 0 else { return nil }

        let scale: CGFloat = 2
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: max(1, Int(ceil(pointSize.width * scale))),
                height: max(1, Int(ceil(pointSize.height * scale))),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()

        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: pointSize))

        guard let cgImage = context.makeImage() else { return nil }
        let output = NSImage(cgImage: cgImage, size: pointSize)
        output.isTemplate = false
        return output
    }
}
