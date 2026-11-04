#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// 生成 README 的正方形宣传主视觉（1200×1200，也可用于仓库封面 / 社交分享图）。
// 黑白极客风 + 黑白红配色：纯黑底、等宽字体、1px 线框、终端命令行；
// 红色只用在「锁定 / 警示」相关的语义位置，其余全是黑白灰。
//
//   swift Tools/make-promo.swift docs/promo.png
//   swift Tools/make-promo.swift /tmp/grid.png --grid   # 叠加对齐参考线，用于排版检查
//
// 全部用 CoreGraphics / SF Symbols 按大尺寸重绘，不用截图：
// 菜单栏图标只有 17pt，截图放大必然发糊。

let arguments = Array(CommandLine.arguments.dropFirst())
let outputPath = arguments.first(where: { !$0.hasPrefix("--") }) ?? "docs/promo.png"
let showGrid = arguments.contains("--grid")

let W: CGFloat = 1200
let H: CGFloat = 1200

// 统一网格：所有外层块共用同一对边缘；卡片内部再用各自的 padding。
let margin: CGFloat = 80
let rightEdge = W - margin                          // 1120
let contentWidth = W - 2 * margin                  // 1040
let heroInset: CGFloat = 32
let heroInnerLeft = margin + heroInset              // 112
let heroInnerWidth = contentWidth - 2 * heroInset  // 976
let heroInnerRight = heroInnerLeft + heroInnerWidth // 1088
let heroCenterX = W / 2                            // 600
let cardGap: CGFloat = 20
let cardWidth = (contentWidth - cardGap) / 2       // 510
let cardHeight: CGFloat = 130
let highlightInset: CGFloat = 32

// 黑、白、两档灰，加上唯一的强调色：系统红（与应用内锁定态一致）
let ink = NSColor(srgbRed: 0.02, green: 0.02, blue: 0.025, alpha: 1)
let paper = NSColor(srgbRed: 0.95, green: 0.96, blue: 0.97, alpha: 1)
let gray = NSColor(srgbRed: 0.58, green: 0.59, blue: 0.61, alpha: 1)
let dim = NSColor(srgbRed: 0.36, green: 0.37, blue: 0.39, alpha: 1)
let onWhite = NSColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1)
let red = NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1)

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [r, g, b, a])!
}

func line(_ r: CGFloat = 1, _ a: CGFloat) -> CGColor { rgba(r, r, r, a) }

let redCG = rgba(1.0, 0.271, 0.227, 1)
func redLine(_ a: CGFloat = 1) -> CGColor { rgba(1.0, 0.271, 0.227, a) }

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

/// 卡片四角的 L 形定位标记，终端 / 仪器面板的味道。
func cornerTicks(_ rect: CGRect, length: CGFloat = 16, color: CGColor = line(1, 0.55)) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(2)
    let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
        (rect.minX, rect.minY, 1, 1),
        (rect.maxX, rect.minY, -1, 1),
        (rect.minX, rect.maxY, 1, -1),
        (rect.maxX, rect.maxY, -1, -1),
    ]
    for (x, y, sx, sy) in corners {
        ctx.move(to: CGPoint(x: x, y: y + sy * length))
        ctx.addLine(to: CGPoint(x: x, y: y))
        ctx.addLine(to: CGPoint(x: x + sx * length, y: y))
        ctx.strokePath()
    }
    ctx.restoreGState()
}

func dashedLine(_ from: CGPoint, _ to: CGPoint,
                color: CGColor = line(1, 0.22), pattern: [CGFloat] = [7, 7]) {
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineWidth(1)
    ctx.setLineDash(phase: 0, lengths: pattern)
    ctx.move(to: from)
    ctx.addLine(to: to)
    ctx.strokePath()
    ctx.restoreGState()
}

func mono(_ size: CGFloat, bold: Bool = false) -> NSFont {
    NSFont(name: bold ? "Menlo-Bold" : "Menlo-Regular", size: size)
        ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
}

/// 中文用苹方，英文默认用等宽；flipped:false 下文字从 rect 顶部往下排，
/// 字形中心 ≈ rect.maxY - lineHeight/2，垂直对齐都按这个算。
func label(_ text: String, _ rect: CGRect, size: CGFloat,
           weight: NSFont.Weight = .regular, color: NSColor,
           kern: CGFloat = 0, alignment: NSTextAlignment = .left,
           chinese: Bool = false) {
    let bold = weight.rawValue >= NSFont.Weight.semibold.rawValue
    var font: NSFont
    if chinese {
        font = NSFont(name: bold ? "PingFangSC-Semibold" : "PingFangSC-Regular", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    } else {
        font = mono(size, bold: bold)
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

/// 等比居中绘制符号；系统若没有该符号，退化成一个细方框，保证版面不塌。
func drawSymbol(_ name: String, in rect: CGRect, color: NSColor,
                weight: NSFont.Weight = .regular) {
    guard let image = tintedSymbol(name, pointSize: 120, weight: weight, color: color) else {
        strokeRound(rect.insetBy(dx: 9, dy: 9), 0, line(1, 0.45), 2)
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

/// 反白安全条上的红底白字方角标签
func tagWidth(_ text: String) -> CGFloat {
    NSAttributedString(string: text, attributes: [.font: mono(15, bold: true)])
        .size().width + 26
}

func tag(_ text: String, x: CGFloat, y: CGFloat, height: CGFloat = 36) -> CGFloat {
    let width = tagWidth(text)
    let rect = CGRect(x: x, y: y, width: width, height: height)
    fillRound(rect, 0, redCG)
    label(text, CGRect(x: x, y: y - 3, width: width, height: 30),
          size: 15, weight: .bold, color: paper, alignment: .center)
    return width
}

// MARK: - 背景：纯黑 + 细网格 + 四角定位标记

fillRound(CGRect(x: 0, y: 0, width: W, height: H), 0, ink.cgColor)
// 1px 外框：深色主题下也能看清图片边界，像终端窗口的边框
strokeRound(CGRect(x: 0.5, y: 0.5, width: W - 1, height: H - 1),
            0, line(1, 0.16), 1)

ctx.saveGState()
ctx.setStrokeColor(line(1, 0.045))
ctx.setLineWidth(1)
for position in stride(from: 40 as CGFloat, through: W - 40, by: 40) {
    ctx.move(to: CGPoint(x: position, y: 0))
    ctx.addLine(to: CGPoint(x: position, y: H))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: 0, y: position))
    ctx.addLine(to: CGPoint(x: W, y: position))
    ctx.strokePath()
}
ctx.restoreGState()

// 网格交点上的小方块，像坐标纸 / 像素点阵
ctx.setFillColor(line(1, 0.10))
for gx in stride(from: 40 as CGFloat, through: W - 40, by: 80) {
    for gy in stride(from: 40 as CGFloat, through: H - 40, by: 80) {
        ctx.fill(CGRect(x: gx - 1, y: gy - 1, width: 2, height: 2))
    }
}

cornerTicks(CGRect(x: 24, y: 24, width: W - 48, height: H - 48), length: 26,
            color: line(1, 0.38))
ctx.setFillColor(line(1, 0.30))
ctx.fill(CGRect(x: margin, y: H - 24, width: contentWidth, height: 1))
ctx.fill(CGRect(x: margin, y: 24, width: contentWidth, height: 1))

// MARK: - 顶部：终端标题区

ctx.setFillColor(redCG)
ctx.fill(CGRect(x: margin, y: 1144, width: 10, height: 10))
label("$ keyboardlocker --status", CGRect(x: margin + 20, y: 1134, width: 500, height: 26),
      size: 18, color: gray)
label("[ macOS 13+ ]", CGRect(x: rightEdge - 500, y: 1134, width: 500, height: 26),
      size: 18, color: dim, alignment: .right)

// 标题：Keyboard 白字，Locker 红底白字块＝唯一的「锁定」强调
let titleFont = mono(92, bold: true)
let titleFirst = NSAttributedString(string: "Keyboard", attributes: [
    .font: titleFont, .foregroundColor: paper, .kern: -1,
])
let titleSecond = NSAttributedString(string: "Locker", attributes: [
    .font: titleFont, .foregroundColor: paper, .kern: -1,
])
let firstWidth = titleFirst.size().width
let secondWidth = titleSecond.size().width
let titleLeft = (W - (firstWidth + secondWidth + 20)) / 2
let titleBox = CGRect(x: 0, y: 972, width: W, height: 140) // maxY 1112，字形中心 ≈1057

titleFirst.draw(with: CGRect(x: titleLeft, y: titleBox.minY,
                             width: firstWidth + 4, height: titleBox.height),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
let highlightRect = CGRect(x: titleLeft + firstWidth + 6, y: 990,
                           width: secondWidth + 14, height: 124)
fillRound(highlightRect, 0, redCG)
titleSecond.draw(with: CGRect(x: highlightRect.minX + 7, y: titleBox.minY,
                              width: secondWidth + 4, height: titleBox.height),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])

label("擦键盘时，一键锁住整个键盘",
      CGRect(x: 0, y: 919, width: W, height: 55),
      size: 40, weight: .semibold, color: paper, kern: 1,
      alignment: .center, chinese: true)
label("> one click  ·  every key blocked  ·  wipe it down in peace",
      CGRect(x: 0, y: 880, width: W, height: 36),
      size: 22, color: gray, alignment: .center)
dashedLine(CGPoint(x: margin, y: 866), CGPoint(x: rightEdge, y: 866))

// MARK: - 中部：状态面板（线框 + 键帽 + 红底 LOCKED 块）

let heroCard = CGRect(x: margin, y: 570, width: contentWidth, height: 280)
fillRound(heroCard, 0, rgba(1, 1, 1, 0.018))
strokeRound(heroCard, 0, line(1, 0.28), 1)
cornerTicks(heroCard, length: 18, color: line(1, 0.75))

// 面板标题栏：左侧编号，右侧菜单栏图标的白色 → 红色状态切换
let barBottom: CGFloat = 814
ctx.setFillColor(line(1, 0.28))
ctx.fill(CGRect(x: heroCard.minX, y: barBottom, width: heroCard.width, height: 1))
label("[ 01 ]  STATUS", CGRect(x: heroInnerLeft, y: 820, width: 400, height: 20),
      size: 15, weight: .bold, color: paper)
drawSymbol("keyboard", in: CGRect(x: 760, y: 823, width: 26, height: 18), color: paper)
label("->", CGRect(x: 794, y: 820, width: 34, height: 20),
      size: 15, color: dim, alignment: .center)
drawSymbol("keyboard.fill", in: CGRect(x: 836, y: 823, width: 26, height: 18), color: red)
label("LOCKED", CGRect(x: 880, y: 820, width: 208, height: 20),
      size: 14, weight: .bold, color: red, alignment: .right)

// 键盘：18 列 × 5 行，全部 1px 线框，少数键染红当作「被吞掉」的信号点
let keyboardFrame = CGRect(x: heroInnerLeft, y: 630,
                           width: heroInnerWidth, height: 160)
strokeRound(keyboardFrame, 0, redCG, 2)

let padX: CGFloat = 20
let padY: CGFloat = 16
let gap: CGFloat = 7
let rows = 5
let cols = 18
let sideKeys = 4
let keyHeight = (keyboardFrame.height - 2 * padY - CGFloat(rows - 1) * gap) / CGFloat(rows)
let keyWidth = (keyboardFrame.width - 2 * padX - CGFloat(cols - 1) * gap) / CGFloat(cols)

func keyRect(_ col: Int, _ rowY: CGFloat) -> CGRect {
    CGRect(x: keyboardFrame.minX + padX + CGFloat(col) * (keyWidth + gap),
           y: rowY, width: keyWidth, height: keyHeight)
}

for row in 0..<rows {
    let y = keyboardFrame.maxY - padY - CGFloat(row + 1) * keyHeight - CGFloat(row) * gap
    if row == rows - 1 {
        let sideWidth = CGFloat(sideKeys) * keyWidth + CGFloat(sideKeys - 1) * gap
        for col in 0..<sideKeys {
            strokeRound(keyRect(col, y), 0, line(1, 0.22), 1)
        }
        let spaceWidth = keyboardFrame.width - 2 * padX - 2 * sideWidth - 2 * gap
        strokeRound(CGRect(x: keyboardFrame.minX + padX + sideWidth + gap,
                           y: y, width: spaceWidth, height: keyHeight),
                    0, line(1, 0.22), 1)
        for col in 0..<sideKeys {
            let x = keyboardFrame.maxX - padX - CGFloat(sideKeys - col) * keyWidth
                - CGFloat(sideKeys - 1 - col) * gap
            strokeRound(CGRect(x: x, y: y, width: keyWidth, height: keyHeight),
                        0, line(1, 0.22), 1)
        }
    } else {
        for col in 0..<cols {
            let rect = keyRect(col, y)
            if (row * 5 + col) % 13 == 0 {
                fillRound(rect, 0, redCG)
            } else {
                strokeRound(rect, 0, line(1, 0.22), 1)
            }
        }
    }
}

// 中央红底状态块：整张图最醒目的「锁定」语义
let lockPlate = CGRect(x: heroCenterX - 180, y: keyboardFrame.midY - 48,
                       width: 360, height: 96)
fillRound(lockPlate, 0, redCG)
label("// LOCKED", CGRect(x: lockPlate.minX, y: lockPlate.minY + 50,
                          width: lockPlate.width, height: 32),
      size: 26, weight: .bold, color: paper, alignment: .center)
label("ALL KEYS DISCARDED", CGRect(x: lockPlate.minX, y: lockPlate.minY + 16,
                                   width: lockPlate.width, height: 24),
      size: 15, color: paper, alignment: .center)

label("> 点一下图标，所有按键立即失去响应",
      CGRect(x: heroInnerLeft, y: 586, width: heroInnerWidth, height: 28),
      size: 21, color: gray, alignment: .center, chinese: true)

// MARK: - 下部：四张功能卡片

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

let gridY: CGFloat = 250

for (index, feature) in features.enumerated() {
    let col = CGFloat(index % 2)
    let row = CGFloat(index / 2)
    let x = margin + col * (cardWidth + cardGap)
    let y = gridY + (1 - row) * (cardHeight + cardGap)
    let rect = CGRect(x: x, y: y, width: cardWidth, height: cardHeight)

    strokeRound(rect, 0, line(1, 0.28), 1)
    cornerTicks(rect, length: 14, color: line(1, 0.65))

    let iconBox = CGRect(x: x + 28, y: y + 41, width: 48, height: 48)
    strokeRound(iconBox, 0, line(1, 0.45), 1)
    drawSymbol(feature.symbol, in: iconBox.insetBy(dx: 11, dy: 11), color: paper,
               weight: .semibold)

    label(String(format: "%02d", index + 1),
          CGRect(x: x + cardWidth - 80, y: y + 96, width: 56, height: 24),
          size: 16, weight: .bold, color: red, alignment: .right)
    label(feature.title, CGRect(x: x + 96, y: y + 65, width: 386, height: 40),
          size: 28, weight: .bold, color: paper)
    label(feature.detail, CGRect(x: x + 96, y: y + 21, width: 386, height: 34),
          size: 20, color: gray, chinese: true)
}

// MARK: - 底部：反白安全条 + 红色警示

let highlight = CGRect(x: margin, y: 110, width: contentWidth, height: 100)
fillRound(highlight, 0, paper.cgColor)
ctx.setFillColor(redCG)
ctx.fill(CGRect(x: highlight.minX, y: highlight.maxY - 4,
                width: highlight.width, height: 4))

let highlightIcon = CGRect(x: margin + highlightInset, y: 138, width: 44, height: 44)
fillRound(highlightIcon, 0, redCG)
drawSymbol("checkmark.shield.fill", in: highlightIcon.insetBy(dx: 10, dy: 10),
           color: paper, weight: .semibold)

let copyLeft = highlightIcon.maxX + 16
label("锁屏即自动解锁 · 密码照常能输",
      CGRect(x: copyLeft, y: 157, width: 500, height: 40),
      size: 30, weight: .semibold, color: onWhite, chinese: true)
label("AUTO-UNLOCK ON SCREEN LOCK / SLEEP",
      CGRect(x: copyLeft, y: 125, width: 500, height: 28),
      size: 18, color: red)

let tags = ["MIT LICENSE", "~450 KB", "macOS 13+"]
let tagGap: CGFloat = 10
let tagsTotal = tags.reduce(0) { $0 + tagWidth($1) } + tagGap * 2
var tagX: CGFloat = rightEdge - highlightInset - tagsTotal
for text in tags {
    tagX += tag(text, x: tagX, y: 142) + tagGap
}

// MARK: - 页脚

dashedLine(CGPoint(x: margin, y: 96), CGPoint(x: rightEdge, y: 96))
ctx.setFillColor(redCG)
ctx.fill(CGRect(x: margin, y: 65, width: 8, height: 8))
label("$ swift  ·  CGEventTap  ·  no dock icon",
      CGRect(x: margin + 18, y: 52, width: 600, height: 28),
      size: 18, color: dim)
label("[ MIT ]  OPEN SOURCE",
      CGRect(x: rightEdge - 500, y: 52, width: 500, height: 28),
      size: 18, color: dim, alignment: .right)

// MARK: - 可选：对齐参考线（仅 --grid 调试输出，正式图不含）
if showGrid {
    ctx.setLineWidth(1)
    for x in [margin, heroInnerLeft, heroCenterX, heroInnerRight,
              margin + cardWidth, margin + cardWidth + cardGap, rightEdge] as [CGFloat] {
        ctx.setStrokeColor(rgba(0.2, 0.9, 1.0, 0.55))
        ctx.move(to: CGPoint(x: x, y: 0))
        ctx.addLine(to: CGPoint(x: x, y: H))
        ctx.strokePath()
    }
    for y in [52, 110, 210, 250, 530, 570, 850, 880, 972, 1134] as [CGFloat] {
        ctx.setStrokeColor(rgba(1.0, 0.85, 0.2, 0.45))
        ctx.move(to: CGPoint(x: 0, y: y))
        ctx.addLine(to: CGPoint(x: W, y: y))
        ctx.strokePath()
    }
}

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
