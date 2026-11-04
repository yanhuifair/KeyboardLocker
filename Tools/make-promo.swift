#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// 生成 README 顶部的宣传主视觉。
//
//   swift Tools/make-promo.swift docs/promo.png
//   swift Tools/make-promo.swift /tmp/grid.png --grid   # 叠加对齐参考线，用于排版检查
//
// 全部用 CoreGraphics / SF Symbols 按大尺寸重绘，不用截图：
// 菜单栏图标只有 17pt，截图放大必然发糊。配色与 docs/menubar.png 保持一致
// （深灰渐变 + 白色线框键盘 + 系统红的锁定态）。

let arguments = Array(CommandLine.arguments.dropFirst())
let outputPath = arguments.first(where: { !$0.hasPrefix("--") }) ?? "docs/promo.png"
let showGrid = arguments.contains("--grid")

let W: CGFloat = 1440
let H: CGFloat = 760

// 统一网格：所有外层块共用同一对边缘；卡片内部再用各自的 padding。
// 每个元素的坐标都从这些常量推导，避免各处手写 magic number 造成几像素的错位。
let margin: CGFloat = 64
let rightEdge = W - margin                      // 1376
let contentWidth = W - 2 * margin              // 1312
let heroWidth: CGFloat = 612
let heroInset: CGFloat = 26                    // 插画卡内部统一内边距
let heroInnerLeft = margin + heroInset         // 90
let heroInnerWidth = heroWidth - 2 * heroInset // 560
let heroInnerRight = heroInnerLeft + heroInnerWidth // 650
let heroCenterX = margin + heroWidth / 2       // 370
let groupGap: CGFloat = 24
let gridX = margin + heroWidth + groupGap      // 700
let cardWidth: CGFloat = 330
let cardHeight: CGFloat = 107
let cardGap: CGFloat = 16
let highlightInset: CGFloat = 28               // 强调条左右内边距

let red = NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)
let paper = NSColor(srgbRed: 0.96, green: 0.965, blue: 0.98, alpha: 1)
let muted = NSColor(srgbRed: 0.68, green: 0.69, blue: 0.73, alpha: 1)
let faint = NSColor(srgbRed: 0.50, green: 0.51, blue: 0.55, alpha: 1)

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [r, g, b, a])!
}

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
        data: nil,
        width: Int(W),
        height: Int(H),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    FileHandle.standardError.write("无法创建绘图上下文\n".data(using: .utf8)!)
    exit(1)
}

ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// MARK: - 绘制原语

func roundedPath(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func fillRound(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor) {
    ctx.saveGState()
    ctx.addPath(roundedPath(rect, radius))
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
}

func strokeRound(_ rect: CGRect, _ radius: CGFloat, _ color: CGColor, _ width: CGFloat = 1) {
    ctx.saveGState()
    ctx.addPath(roundedPath(rect, radius))
    ctx.setStrokeColor(color)
    ctx.setLineWidth(width)
    ctx.strokePath()
    ctx.restoreGState()
}

func gradientRound(_ rect: CGRect, _ radius: CGFloat, _ colors: [CGColor],
                   _ start: CGPoint, _ end: CGPoint) {
    ctx.saveGState()
    ctx.addPath(roundedPath(rect, radius))
    ctx.clip()
    if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray,
                                 locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
    }
    ctx.restoreGState()
}

/// 中文用苹方，英文用系统字体，避免 SF 对中文回退成细体。
func label(_ text: String, _ rect: CGRect, size: CGFloat,
           weight: NSFont.Weight = .regular, color: NSColor,
           kern: CGFloat = 0, alignment: NSTextAlignment = .left,
           chinese: Bool = false) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if chinese {
        let name = weight.rawValue >= NSFont.Weight.semibold.rawValue
            ? "PingFangSC-Semibold" : "PingFangSC-Regular"
        if let pingfang = NSFont(name: name, size: size) { font = pingfang }
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: kern,
        .paragraphStyle: paragraph,
    ]
    NSAttributedString(string: text, attributes: attributes)
        .draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
}

/// 把 SF Symbol 的 template 蒙版整体染色，返回真正的位图。
func tintedSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight,
                  color: NSColor) -> CGImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return nil }

    let size = base.size
    let scale: CGFloat = 3
    let pixelWidth = max(1, Int(ceil(size.width * scale)))
    let pixelHeight = max(1, Int(ceil(size.height * scale)))

    guard let ctx2 = CGContext(
        data: nil, width: pixelWidth, height: pixelHeight,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx2.scaleBy(x: scale, y: scale)
    ctx2.setAllowsAntialiasing(true)
    ctx2.interpolationQuality = .high

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx2, flipped: false)
    base.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()

    ctx2.setBlendMode(.sourceIn)
    ctx2.setFillColor(color.cgColor)
    ctx2.fill(CGRect(origin: .zero, size: size))
    return ctx2.makeImage()
}

/// 等比居中绘制符号；系统若没有该符号，退化成一个细圆环，保证版面不塌。
func drawSymbol(_ name: String, in rect: CGRect, color: NSColor,
                weight: NSFont.Weight = .regular) {
    guard let image = tintedSymbol(name, pointSize: 120, weight: weight, color: color) else {
        ctx.saveGState()
        ctx.setStrokeColor(rgba(1, 1, 1, 0.45))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: rect.insetBy(dx: 9, dy: 9))
        ctx.restoreGState()
        return
    }
    let ratio = CGFloat(image.width) / CGFloat(image.height)
    var width = rect.height * ratio
    var height = rect.height
    if width > rect.width {
        width = rect.width
        height = width / ratio
    }
    ctx.draw(image, in: CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2,
                               width: width, height: height))
}

let pillFont = NSFont.systemFont(ofSize: 17, weight: .semibold)

func pillWidth(_ text: String) -> CGFloat {
    NSAttributedString(string: text, attributes: [.font: pillFont]).size().width + 34
}

func pill(_ text: String, x: CGFloat, y: CGFloat, height: CGFloat = 36) -> CGFloat {
    let width = pillWidth(text)
    let rect = CGRect(x: x, y: y, width: width, height: height)
    fillRound(rect, height / 2, rgba(1, 1, 1, 0.07))
    strokeRound(rect, height / 2, rgba(1, 1, 1, 0.13), 1)
    // 文字容器在 flipped:false 下是从 rect 顶部往下排的：
    // 17pt 的字形中心 ≈ rect.maxY - 10。要落在胶囊中线 y + height/2 = y + 18，
    // 需 rect.maxY = y + 28，即 minY = y - 2。
    label(text, CGRect(x: x, y: y - 2, width: width, height: 30),
          size: 17, weight: .semibold, color: NSColor(white: 0.86, alpha: 1),
          alignment: .center)
    return width
}

// MARK: - 背景

let canvas = CGRect(x: 0, y: 0, width: W, height: H)
ctx.saveGState()
ctx.addPath(roundedPath(canvas, 30))
ctx.clip()

gradientRound(canvas, 30,
              [rgba(0.157, 0.161, 0.184), rgba(0.075, 0.078, 0.094)],
              CGPoint(x: 0, y: H), CGPoint(x: 0, y: 0))

// 锁定态的红色在右上角洇开一点，压住整张图的深灰
if let glow = CGGradient(colorsSpace: space,
                         colors: [rgba(1.0, 0.271, 0.227, 0.20),
                                  rgba(1.0, 0.271, 0.227, 0.0)] as CFArray,
                         locations: [0, 1]) {
    ctx.drawRadialGradient(glow,
                           startCenter: CGPoint(x: 1180, y: 500), startRadius: 0,
                           endCenter: CGPoint(x: 1180, y: 500), endRadius: 560,
                           options: [])
}

// 极淡的同心圆，给纯色背景一点层次
ctx.setStrokeColor(rgba(1, 1, 1, 0.028))
ctx.setLineWidth(1)
for radius in stride(from: 150 as CGFloat, through: 750, by: 120) {
    ctx.strokeEllipse(in: CGRect(x: 1180 - radius, y: 500 - radius,
                                 width: radius * 2, height: radius * 2))
}

// 顶部一道细微高光
ctx.setFillColor(rgba(1, 1, 1, 0.07))
ctx.fill(CGRect(x: 40, y: H - 1, width: W - 80, height: 1))

// MARK: - 顶部标题

let eyebrow = "A TINY MENU BAR APP FOR MACOS"
let eyebrowFont = NSFont.systemFont(ofSize: 17, weight: .semibold)
let eyebrowWidth = NSAttributedString(
    string: eyebrow, attributes: [.font: eyebrowFont, .kern: 3]
).size().width

// 红点 + 文字作为一个整体居中，而不是把文字单独居中再把点挂在外面。
// 文字宽度必须用与实际绘制相同的字重和字距来量，否则红点会差几像素。
let dotSize: CGFloat = 9
let dotGap: CGFloat = 13
let eyebrowLeft = (W - (dotSize + dotGap + eyebrowWidth)) / 2
ctx.setFillColor(red.cgColor)
ctx.fillEllipse(in: CGRect(x: eyebrowLeft, y: 722, width: dotSize, height: dotSize))
label(eyebrow,
      CGRect(x: eyebrowLeft + dotSize + dotGap - 1, y: 710,
             width: eyebrowWidth + 2, height: 26),
      size: 17, weight: .semibold, color: faint, kern: 3, alignment: .center)

// 标题：Locker 用锁定红，直接把产品语义写进字里
let titleFont = NSFont.systemFont(ofSize: 92, weight: .bold)
let title = NSMutableAttributedString()
title.append(NSAttributedString(string: "Keyboard", attributes: [
    .font: titleFont, .foregroundColor: paper, .kern: -2,
]))
title.append(NSAttributedString(string: "Locker", attributes: [
    .font: titleFont, .foregroundColor: red, .kern: -2,
]))
let titleWidth = title.size().width
let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
title.addAttribute(.paragraphStyle, value: titleStyle,
                   range: NSRange(location: 0, length: title.length))
// 左右各留 6px 余量防止浮点舍入换行，居中交给段落样式
title.draw(with: CGRect(x: (W - titleWidth) / 2 - 6, y: 590,
                        width: titleWidth + 12, height: 118),
           options: [.usesLineFragmentOrigin, .usesFontLeading])

label("擦键盘时，一键锁住整个键盘",
      CGRect(x: 0, y: 536, width: W, height: 48),
      size: 36, weight: .semibold, color: paper, kern: 1, alignment: .center, chinese: true)
label("One click. Every key blocked. Wipe it down in peace.",
      CGRect(x: 0, y: 496, width: W, height: 34),
      size: 24, color: muted, alignment: .center)

// MARK: - 左侧：锁定态键盘插画
// 卡片内部三块元素（菜单栏胶囊 / 键盘 / 说明文字）共用 x=90..650 的网格，
// 垂直间距统一为 10px：478→472(6) / 472→430(10) / 292→282(10) / 258→248(10)。
let heroCard = CGRect(x: margin, y: 248, width: heroWidth, height: 230)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26,
              color: rgba(0, 0, 0, 0.35))
fillRound(heroCard, 24, rgba(1, 1, 1, 0.045))
ctx.restoreGState()
strokeRound(heroCard, 24, rgba(1, 1, 1, 0.10), 1)

// 模拟菜单栏：所有元素共用胶囊中线 y=456
let bar = CGRect(x: heroInnerLeft, y: 440, width: heroInnerWidth, height: 32)
fillRound(bar, 16, rgba(0, 0, 0, 0.24))
label("MENU BAR", CGRect(x: heroInnerLeft + 18, y: 444, width: 130, height: 20),
      size: 14, weight: .semibold, color: faint, kern: 1.4)
for i in 0..<3 {
    ctx.setFillColor(rgba(1, 1, 1, 0.16))
    ctx.fillEllipse(in: CGRect(x: 240 + CGFloat(i) * 18, y: 452, width: 8, height: 8))
}
drawSymbol("keyboard", in: CGRect(x: 456, y: 447, width: 26, height: 18), color: paper)
ctx.saveGState()
ctx.setStrokeColor(rgba(1, 1, 1, 0.42))
ctx.setLineWidth(2)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: 494, y: 456))
ctx.addLine(to: CGPoint(x: 514, y: 456))
ctx.move(to: CGPoint(x: 508, y: 461))
ctx.addLine(to: CGPoint(x: 514, y: 456))
ctx.addLine(to: CGPoint(x: 508, y: 451))
ctx.strokePath()
ctx.restoreGState()
drawSymbol("keyboard.fill", in: CGRect(x: 526, y: 447, width: 26, height: 18), color: red)
label("LOCKED", CGRect(x: 562, y: 444, width: 70, height: 20),
      size: 13, weight: .bold, color: red, kern: 1)

// 键盘本体：手工画键帽，不放大位图，缩放后依然锐利
let keyboardFrame = CGRect(x: heroInnerLeft, y: 292,
                           width: heroInnerWidth, height: 138)
gradientRound(keyboardFrame, 18,
              [rgba(0.215, 0.222, 0.251), rgba(0.098, 0.102, 0.120)],
              CGPoint(x: 0, y: keyboardFrame.maxY),
              CGPoint(x: 0, y: keyboardFrame.minY))
strokeRound(keyboardFrame, 18, rgba(1, 0.45, 0.42, 0.55), 2)

let padX: CGFloat = 20
let padY: CGFloat = 16
let gap: CGFloat = 7
let rows = 5
let cols = 14
let keyHeight = (keyboardFrame.height - 2 * padY - CGFloat(rows - 1) * gap) / CGFloat(rows)
let keyWidth = (keyboardFrame.width - 2 * padX - CGFloat(cols - 1) * gap) / CGFloat(cols)

for row in 0..<rows {
    let y = keyboardFrame.maxY - padY - CGFloat(row + 1) * keyHeight - CGFloat(row) * gap
    if row == rows - 1 {
        let sideWidth = 3 * keyWidth + 2 * gap
        for col in 0..<3 {
            fillRound(CGRect(x: keyboardFrame.minX + padX + CGFloat(col) * (keyWidth + gap),
                             y: y, width: keyWidth, height: keyHeight), 4,
                      rgba(1, 1, 1, 0.14))
        }
        let spaceWidth = keyboardFrame.width - 2 * padX - 2 * sideWidth - 2 * gap
        fillRound(CGRect(x: keyboardFrame.minX + padX + sideWidth + gap,
                         y: y, width: spaceWidth, height: keyHeight), 4,
                  rgba(1, 1, 1, 0.14))
        for col in 0..<3 {
            fillRound(CGRect(x: keyboardFrame.maxX - padX - CGFloat(3 - col) * keyWidth
                             - CGFloat(2 - col) * gap,
                             y: y, width: keyWidth, height: keyHeight), 4,
                      rgba(1, 1, 1, 0.14))
        }
    } else {
        for col in 0..<cols {
            fillRound(CGRect(x: keyboardFrame.minX + padX + CGFloat(col) * (keyWidth + gap),
                             y: y, width: keyWidth, height: keyHeight), 4,
                      rgba(1, 1, 1, 0.14))
        }
    }
}

// 中央锁徽标，与键盘共用中心 x
let badgeSize: CGFloat = 86
let badge = CGRect(x: keyboardFrame.midX - badgeSize / 2,
                   y: keyboardFrame.midY - badgeSize / 2,
                   width: badgeSize, height: badgeSize)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20,
              color: rgba(0, 0, 0, 0.50))
ctx.setFillColor(rgba(1.0, 0.271, 0.227, 1))
ctx.fillEllipse(in: badge)
ctx.restoreGState()
ctx.saveGState()
ctx.addEllipse(in: badge)
ctx.clip()
if let badgeGradient = CGGradient(colorsSpace: space,
                                  colors: [rgba(1.0, 0.40, 0.34, 1),
                                           rgba(0.85, 0.10, 0.11, 1)] as CFArray,
                                  locations: [0, 1]) {
    ctx.drawLinearGradient(badgeGradient,
                           start: CGPoint(x: 0, y: badge.maxY),
                           end: CGPoint(x: 0, y: badge.minY), options: [])
}
ctx.restoreGState()
drawSymbol("lock.fill", in: badge.insetBy(dx: 25, dy: 25), color: .white, weight: .bold)

label("点一下图标，所有按键立即失去响应",
      CGRect(x: heroInnerLeft, y: 258, width: heroInnerWidth, height: 26),
      size: 19, color: muted, alignment: .center, chinese: true)

// MARK: - 右侧：四张功能卡片
// 组内间距 16、组间 24；2×330 + 16 恰好让右边缘落在 rightEdge(1376)。
struct Feature {
    let symbol: String
    let title: String
    let detail: String
}

let features = [
    Feature(symbol: "keyboard", title: "Every key", detail: "字母 · 修饰键 · 媒体键"),
    Feature(symbol: "lock.open.fill", title: "Never stuck", detail: "锁屏 / 睡眠自动解锁"),
    Feature(symbol: "menubar.rectangle", title: "Zero clutter", detail: "没有窗口和弹窗"),
    Feature(symbol: "cursorarrow", title: "Mouse stays free", detail: "解锁不依赖键盘"),
]

let gridY: CGFloat = 248

for (index, feature) in features.enumerated() {
    let col = CGFloat(index % 2)
    let row = CGFloat(index / 2)
    let x = gridX + col * (cardWidth + cardGap)
    let y = gridY + (1 - row) * (cardHeight + cardGap)
    let rect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20,
                  color: rgba(0, 0, 0, 0.28))
    fillRound(rect, 20, rgba(1, 1, 1, 0.045))
    ctx.restoreGState()
    strokeRound(rect, 20, rgba(1, 1, 1, 0.10), 1)

    // 图标与两行文字块共用卡片中线：图标中心 y+54，文字块中心 y+53.85，
    // 卡片几何中心 y+53.5，三者误差不到 1px。
    let iconBox = CGRect(x: x + 24, y: y + 34, width: 40, height: 40)
    fillRound(iconBox, 12, rgba(1.0, 0.271, 0.227, 0.13))
    drawSymbol(feature.symbol, in: iconBox.insetBy(dx: 9, dy: 9), color: red,
               weight: .semibold)

    label(feature.title, CGRect(x: x + 80, y: y + 51, width: 226, height: 36),
          size: 26, weight: .bold, color: paper)
    label(feature.detail, CGRect(x: x + 80, y: y + 15, width: 226, height: 32),
          size: 18, color: muted, chinese: true)
}

// MARK: - 底部：最打动人的一条安全保障
// 左右内边距同为 28：图标 x=92，pill 组右边缘 1348。
let highlight = CGRect(x: margin, y: 106, width: contentWidth, height: 100)
gradientRound(highlight, 22,
              [rgba(1.0, 0.271, 0.227, 0.20), rgba(1.0, 0.271, 0.227, 0.055)],
              CGPoint(x: highlight.minX, y: 0), CGPoint(x: highlight.maxX, y: 0))
strokeRound(highlight, 22, rgba(1.0, 0.40, 0.34, 0.40), 1.5)

let highlightIcon = CGRect(x: margin + highlightInset, y: 134, width: 44, height: 44)
fillRound(highlightIcon, 13, rgba(1.0, 0.271, 0.227, 0.20))
drawSymbol("checkmark.shield.fill", in: highlightIcon.insetBy(dx: 10, dy: 10),
           color: red, weight: .semibold)

let copyLeft = highlightIcon.maxX + 16
label("锁屏即自动解锁 · 回来永远能输入密码",
      CGRect(x: copyLeft, y: 152, width: 760, height: 40),
      size: 29, weight: .semibold, color: paper, chinese: true)
label("Auto-unlock on screen lock / sleep — the login password always works.",
      CGRect(x: copyLeft, y: 120, width: 780, height: 28),
      size: 19, color: muted)

let pills = ["MIT LICENSE", "~450 KB", "macOS 13+"]
let pillGap: CGFloat = 10
let pillsTotal = pills.reduce(0) { $0 + pillWidth($1) } + pillGap * 2
var pillX: CGFloat = rightEdge - highlightInset - pillsTotal
for text in pills {
    pillX += pill(text, x: pillX, y: 138) + pillGap
}

// MARK: - 页脚：与上方卡片共用 margin / rightEdge
label("Swift · CGEventTap · 仅菜单栏",
      CGRect(x: margin, y: 46, width: 500, height: 26),
      size: 18, color: faint, chinese: true)
label("Open source · No dependencies",
      CGRect(x: rightEdge - 500, y: 46, width: 500, height: 26),
      size: 18, color: faint, alignment: .right)

// MARK: - 可选：对齐参考线（仅 --grid 调试输出，正式图不含）
if showGrid {
    ctx.setLineWidth(1)
    for x in [margin, heroInnerLeft, heroCenterX, heroInnerRight,
              margin + heroWidth, gridX, gridX + cardWidth,
              gridX + cardWidth + cardGap, rightEdge] as [CGFloat] {
        ctx.setStrokeColor(rgba(0.2, 0.9, 1.0, 0.55))
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: H))
        ctx.strokePath()
    }
    for y in [46, 106, 206, 248, 478, 590, 710] as [CGFloat] {
        ctx.setStrokeColor(rgba(1.0, 0.85, 0.2, 0.45))
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: W, y: y))
        ctx.strokePath()
    }
}

ctx.restoreGState() // 整幅圆角裁剪
NSGraphicsContext.restoreGraphicsState()

// MARK: - 输出

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write("无法生成图片\n".data(using: .utf8)!)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                          withIntermediateDirectories: true)
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 编码失败\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: url)
    print("saved \(url.path)  \(Int(W))x\(Int(H))\(showGrid ? "  [grid]" : "")")
} catch {
    FileHandle.standardError.write("写入失败: \(error)\n".data(using: .utf8)!)
    exit(1)
}
