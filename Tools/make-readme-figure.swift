import AppKit
import CoreGraphics
import Foundation

// 生成 README 用的菜单栏状态展示图。
//
//   swift Tools/make-readme-figure.swift docs/menubar.png
//
// 不用屏幕截图：菜单栏图标只有 17pt，截图放大后必然发糊，还会带进
// 壁纸颜色和相邻图标的残影。这里直接按大尺寸重新渲染 SF Symbol。

let outputPath = CommandLine.arguments.dropFirst().first ?? "docs/menubar.png"

let width = 1200
let height = 300
let cornerRadius: CGFloat = 26

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [r, g, b, a])!
}

/// 把 SF Symbol 的 template 蒙版整体染成指定颜色，返回真正的位图。
func tintedSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> CGImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration)
    else { return nil }

    let size = base.size
    let scale: CGFloat = 3
    let pixelWidth = max(1, Int(ceil(size.width * scale)))
    let pixelHeight = max(1, Int(ceil(size.height * scale)))

    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { return nil }

    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    base.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()

    context.setBlendMode(.sourceIn)
    context.setFillColor(color.cgColor)
    context.fill(CGRect(origin: .zero, size: size))

    return context.makeImage()
}

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    FileHandle.standardError.write("无法创建绘图上下文\n".data(using: .utf8)!)
    exit(1)
}

context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

// ---------------------------------------------------------------- 卡片背景
let card = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
context.addPath(CGPath(roundedRect: card, cornerWidth: cornerRadius,
                       cornerHeight: cornerRadius, transform: nil))
context.clip()

let top = srgb(0.176, 0.180, 0.196)
let bottom = srgb(0.106, 0.110, 0.125)
if let gradient = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray,
                             locations: [0, 1]) {
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: CGFloat(height)),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
}

// 顶部一道细微高光，让卡片看起来像贴在菜单栏上的玻璃片
context.setFillColor(srgb(1, 1, 1, 0.07))
context.fill(CGRect(x: cornerRadius, y: CGFloat(height) - 1,
                    width: CGFloat(width) - cornerRadius * 2, height: 1))

// ---------------------------------------------------------------- 两个图标
guard let idle = tintedSymbol("keyboard", pointSize: 116, weight: .regular,
                              color: NSColor(calibratedWhite: 0.96, alpha: 1)),
      let locked = tintedSymbol("keyboard.fill", pointSize: 116, weight: .regular,
                                color: NSColor(srgbRed: 1.0, green: 0.271, blue: 0.227, alpha: 1))
else {
    FileHandle.standardError.write("无法渲染键盘符号\n".data(using: .utf8)!)
    exit(1)
}

let iconHeight: CGFloat = 140
func drawIcon(_ image: CGImage, centerX: CGFloat, centerY: CGFloat) {
    let ratio = CGFloat(image.width) / CGFloat(image.height)
    let iconWidth = iconHeight * ratio
    context.draw(image, in: CGRect(x: centerX - iconWidth / 2,
                                   y: centerY - iconHeight / 2,
                                   width: iconWidth,
                                   height: iconHeight))
}

let iconCenterY: CGFloat = 185
drawIcon(idle, centerX: 330, centerY: iconCenterY)
drawIcon(locked, centerX: 870, centerY: iconCenterY)

// ---------------------------------------------------------------- 箭头
context.setStrokeColor(srgb(1, 1, 1, 0.42))
context.setLineWidth(3)
context.setLineCap(.round)
context.setLineJoin(.round)
let ax: CGFloat = 600
let ay: CGFloat = iconCenterY
context.move(to: CGPoint(x: ax - 24, y: ay))
context.addLine(to: CGPoint(x: ax + 24, y: ay))
context.move(to: CGPoint(x: ax + 12, y: ay + 12))
context.addLine(to: CGPoint(x: ax + 24, y: ay))
context.addLine(to: CGPoint(x: ax + 12, y: ay - 12))
context.strokePath()

// ---------------------------------------------------------------- 标签
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

func label(_ text: String, centerX: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: NSColor(srgbRed: 0.72, green: 0.73, blue: 0.77, alpha: 1),
        .kern: 1.2,
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(in: NSRect(x: centerX - size.width / 2, y: 46,
                           width: size.width, height: size.height))
}

label("IDLE", centerX: 330)
label("LOCKED", centerX: 870)

NSGraphicsContext.restoreGraphicsState()

// ---------------------------------------------------------------- 输出
guard let image = context.makeImage() else {
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
try png.write(to: url)
print("saved \(url.path)  \(width)x\(height)")
