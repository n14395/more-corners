// Generates AppIcon.icns for MoreCorners.
// Usage: swift scripts/make-icon.swift   (run from the repo root)
// Renders the icon at 1024pt with CoreGraphics, emits an .iconset at all
// standard sizes, then packs it with iconutil.

import AppKit
import ImageIO

let canvasSize: CGFloat = 1024

func drawIcon(_ ctx: CGContext) {
    // Standard macOS icon proportions: content squircle inset ~100pt at 1024.
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185,
                          transform: nil)
    ctx.addPath(squircle)
    ctx.clip()

    // Background: deep indigo gradient, lighter toward the top-left.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let colors = [
        CGColor(srgbRed: 0.20, green: 0.22, blue: 0.46, alpha: 1),
        CGColor(srgbRed: 0.05, green: 0.06, blue: 0.16, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY),
                           options: [])

    // Four corner brackets with a cyan glow — the hot corners.
    let inner = rect.insetBy(dx: 190, dy: 190)
    let arm: CGFloat = 150
    let cyan = CGColor(srgbRed: 0.31, green: 0.82, blue: 1.0, alpha: 1)

    func bracket(_ cornerX: CGFloat, _ cornerY: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
        ctx.move(to: CGPoint(x: cornerX + dx * arm, y: cornerY))
        ctx.addLine(to: CGPoint(x: cornerX, y: cornerY))
        ctx.addLine(to: CGPoint(x: cornerX, y: cornerY + dy * arm))
        ctx.strokePath()
    }

    func strokeBrackets() {
        bracket(inner.minX, inner.maxY, 1, -1)
        bracket(inner.maxX, inner.maxY, -1, -1)
        bracket(inner.minX, inner.minY, 1, 1)
        bracket(inner.maxX, inner.minY, -1, 1)
    }

    ctx.setLineWidth(42)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setStrokeColor(cyan)

    // Glow pass, then a crisp pass on top.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 70,
                  color: CGColor(srgbRed: 0.31, green: 0.82, blue: 1.0, alpha: 0.9))
    strokeBrackets()
    ctx.restoreGState()
    strokeBrackets()

    // White pointer arrowing into the top-left corner.
    // Classic arrow outline in a y-down unit space, tip at (0, 0).
    let arrow: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 16.5), CGPoint(x: 4.6, y: 12.8),
        CGPoint(x: 7.4, y: 19.2), CGPoint(x: 10.0, y: 18.1),
        CGPoint(x: 7.3, y: 12.0), CGPoint(x: 12.7, y: 12.0),
    ]
    ctx.saveGState()
    ctx.translateBy(x: inner.minX + 70, y: inner.maxY - 70)
    ctx.scaleBy(x: 24, y: -24)  // flip: path space is y-down, CG is y-up
    ctx.setShadow(offset: CGSize(width: 0, height: -0.4), blur: 1.2,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.beginPath()
    ctx.addLines(between: arrow)
    ctx.closePath()
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
}

func render(px: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let scale = CGFloat(px) / canvasSize
    ctx.scaleBy(x: scale, y: scale)
    drawIcon(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString,
                                               1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                    (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = pt * scale
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    writePNG(render(px: px), to: iconset.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "AppIcon.iconset", "-o", "AppIcon.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote AppIcon.icns" : "iconutil failed")
