#!/usr/bin/env swift
import AppKit

// 生成 1024×1024 的 KeyboardLocker 应用图标。
// 用法: swift Tools/make-icon.swift <输出路径.png>

setvbuf(stdout, nil, _IONBF, 0)

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("用法: swift Tools/make-icon.swift <输出路径.png>")
    exit(1)
}
let outputURL = URL(fileURLWithPath: arguments[1])

let canvas: CGFloat = 1024

let renderer = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
    let inset = canvas * 0.094
    let body = rect.insetBy(dx: inset, dy: inset)
    let corner = body.width * 0.2237

    // ---- 底板 ----
    let plate = NSBezierPath(roundedRect: body, xRadius: corner, yRadius: corner)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.40)
    shadow.shadowBlurRadius = canvas * 0.026
    shadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.010)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1).setFill()
    plate.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    plate.addClip()

    let background = NSGradient(colors: [
        NSColor(srgbRed: 0.215, green: 0.222, blue: 0.251, alpha: 1),
        NSColor(srgbRed: 0.078, green: 0.082, blue: 0.098, alpha: 1),
    ])
    background?.draw(in: plate, angle: -90)

    // 顶部柔光
    let glow = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.10),
        NSColor.white.withAlphaComponent(0.0),
    ])
    glow?.draw(in: NSBezierPath(rect: NSRect(
        x: body.minX,
        y: body.midY - body.height * 0.08,
        width: body.width,
        height: body.height * 0.58
    )), angle: -90)

    NSGraphicsContext.restoreGraphicsState()

    // 内描边，让边缘在浅色背景上也能立住
    NSGraphicsContext.saveGraphicsState()
    let border = NSBezierPath(
        roundedRect: body.insetBy(dx: 1.5, dy: 1.5),
        xRadius: corner - 1.5,
        yRadius: corner - 1.5
    )
    border.lineWidth = 3
    NSColor.white.withAlphaComponent(0.10).setStroke()
    border.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // ---- 键盘 ----
    let keyboardSymbol = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: canvas * 0.30, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [
                    NSColor.white.withAlphaComponent(0.94),
                ]))
        )

    if let keyboardSymbol, keyboardSymbol.size.width > 0 {
        let targetWidth = body.width * 0.64
        let scale = targetWidth / keyboardSymbol.size.width
        let size = NSSize(
            width: keyboardSymbol.size.width * scale,
            height: keyboardSymbol.size.height * scale
        )
        let origin = NSPoint(
            x: body.midX - size.width / 2,
            y: body.midY - size.height / 2 + canvas * 0.080
        )
        keyboardSymbol.draw(in: NSRect(origin: origin, size: size))
    }

    // ---- 锁徽标 ----
    let badgeDiameter = body.width * 0.372
    let badgeRect = NSRect(
        x: body.maxX - badgeDiameter - body.width * 0.055,
        y: body.minY + body.width * 0.075,
        width: badgeDiameter,
        height: badgeDiameter
    )

    NSGraphicsContext.saveGraphicsState()
    let badgeShadow = NSShadow()
    badgeShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    badgeShadow.shadowBlurRadius = canvas * 0.018
    badgeShadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.006)
    badgeShadow.set()

    let badge = NSBezierPath(ovalIn: badgeRect)
    NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.40, blue: 0.34, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.10, blue: 0.11, alpha: 1),
    ])?.draw(in: badge, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    if let lockSymbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: badgeDiameter * 0.50, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
        ), lockSymbol.size.width > 0 {
        let scale = (badgeDiameter * 0.52) / lockSymbol.size.height
        let size = NSSize(
            width: lockSymbol.size.width * scale,
            height: lockSymbol.size.height * scale
        )
        lockSymbol.draw(in: NSRect(
            x: badgeRect.midX - size.width / 2,
            y: badgeRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        ))
    }

    return true
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas),
    pixelsHigh: Int(canvas),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    print("无法创建位图缓冲区")
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
renderer.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas))
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    print("无法编码 PNG")
    exit(1)
}

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: outputURL)
    print("已生成图标: \(outputURL.path)")
} catch {
    print("写入失败: \(error)")
    exit(1)
}
