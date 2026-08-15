import AppKit

/// Optional feedback when a corner action fires — any combination of a corner
/// glow flash, a system sound, and a trackpad haptic, per the user's settings.
/// Called on the main thread from `CornerMonitor.fire`.
enum TriggerFeedback {
    static func play(corner: Corner, on screen: NSScreen) {
        let s = AppSettings.shared
        if s.feedbackHaptic {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if s.feedbackSound, !s.feedbackSoundName.isEmpty {
            NSSound(named: s.feedbackSoundName)?.play()
        }
        if s.feedbackFlash {
            flash(corner: corner, on: screen)
        }
    }

    /// Retains the flash windows for the duration of their fade-out animation.
    private static var activeFlashes: [NSWindow] = []

    private static func flash(corner: Corner, on screen: NSScreen) {
        let side: CGFloat = 160
        let cornerPoint = CornerMonitor.point(of: corner, in: screen.frame)  // bottom-left origin
        let origin = CGPoint(x: corner.isLeft ? cornerPoint.x : cornerPoint.x - side,
                             y: corner.isBottom ? cornerPoint.y : cornerPoint.y - side)
        let window = NSWindow(contentRect: NSRect(origin: origin,
                                                  size: CGSize(width: side, height: side)),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces,
                                     .fullScreenAuxiliary]
        window.contentView = CornerGlowView(corner: corner)
        window.orderFrontRegardless()
        activeFlashes.append(window)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            activeFlashes.removeAll { $0 === window }
        })
    }
}

/// A live overlay that highlights the actual hot-corner trigger zones while the
/// user drags the "Corner size" slider, so they can see what a given size covers.
/// One small square per corner of each active screen; `show` while editing,
/// `update` as the value changes, `hide` when done. Main-thread only.
enum CornerZonePreview {
    private static var windows: [NSWindow] = []

    static func show(size: CGFloat) {
        hide()
        for screen in screens() {
            for corner in Corner.allCases {
                let window = makeWindow(corner: corner, size: size, screen: screen)
                window.orderFrontRegardless()
                windows.append(window)
            }
        }
    }

    static func update(size: CGFloat) {
        guard !windows.isEmpty else { return }
        var index = 0
        for screen in screens() {
            for corner in Corner.allCases where index < windows.count {
                windows[index].setFrame(frame(corner: corner, size: size, screen: screen),
                                        display: true)
                windows[index].contentView?.needsDisplay = true
                index += 1
            }
        }
    }

    static func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private static func screens() -> [NSScreen] {
        AppSettings.shared.allScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
    }

    /// The size×size square hugging a corner, in global (bottom-left-origin)
    /// screen coordinates — the on-screen half of the ±size trigger zone.
    private static func frame(corner: Corner, size: CGFloat, screen: NSScreen) -> NSRect {
        let f = screen.frame
        return NSRect(x: corner.isLeft ? f.minX : f.maxX - size,
                      y: corner.isBottom ? f.minY : f.maxY - size,
                      width: size, height: size)
    }

    private static func makeWindow(corner: Corner, size: CGFloat, screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: frame(corner: corner, size: size, screen: screen),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces,
                                     .fullScreenAuxiliary]
        window.contentView = ZonePreviewView()
        return window
    }
}

/// A filled, outlined accent square filling its window — the visible zone patch.
private final class ZonePreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        ctx.setFillColor(accent.withAlphaComponent(0.35).cgColor)
        ctx.fill(bounds)
        ctx.setStrokeColor(accent.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(bounds.insetBy(dx: 1, dy: 1))
    }
}

/// The dwell-progress HUD: while the pointer dwells in a corner, a small pill
/// near that corner shows a ring filling over the dwell duration and the name
/// of the action that will fire. One shared window, repositioned per corner;
/// `CornerMonitor` drives it every tick and hides it when nothing is dwelling.
/// Main-thread only.
enum DwellHint {
    private static var window: NSWindow?
    private static var view: DwellHintView?

    static func show(corner: Corner, on screen: NSScreen, progress: Double, label: String) {
        let height: CGFloat = 36
        let textWidth = label.isEmpty ? 0
            : ceil((label as NSString).size(withAttributes: DwellHintView.captionAttributes).width)
        let width = min(300, height + (textWidth == 0 ? 0 : textWidth + 16))

        // Anchor the pill just inside the corner that is dwelling.
        let cp = CornerMonitor.point(of: corner, in: screen.frame)  // bottom-left origin
        let margin: CGFloat = 14
        let x = corner.isLeft ? cp.x + margin : cp.x - margin - width
        let y = corner.isBottom ? cp.y + margin : cp.y - margin - height
        let frame = NSRect(x: x, y: y, width: width, height: height)

        if window == nil {
            let w = NSWindow(contentRect: frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.level = .screenSaver
            w.ignoresMouseEvents = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces,
                                    .fullScreenAuxiliary]
            let v = DwellHintView()
            w.contentView = v
            window = w
            view = v
        }
        window?.setFrame(frame, display: false)
        view?.corner = corner
        view?.progress = progress
        view?.label = label
        view?.needsDisplay = true
        window?.orderFrontRegardless()
    }

    static func hide() {
        window?.orderOut(nil)
    }
}

/// The pill's content: a progress ring on the corner side, the caption beside it.
private final class DwellHintView: NSView {
    var corner: Corner = .topLeft
    var progress: Double = 0
    var label: String = ""

    static let captionAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor.labelColor,
    ]

    override func draw(_ dirtyRect: NSRect) {
        // Pill background so the caption stays readable over any wallpaper.
        let pill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                xRadius: bounds.height / 2 - 1,
                                yRadius: bounds.height / 2 - 1)
        NSColor.windowBackgroundColor.withAlphaComponent(0.88).setFill()
        pill.fill()
        NSColor.separatorColor.setStroke()
        pill.lineWidth = 1
        pill.stroke()

        // Ring on the side nearest the corner.
        let diameter: CGFloat = 20
        let inset = (bounds.height - diameter) / 2
        let ringX = corner.isLeft ? inset : bounds.width - inset - diameter
        let ring = NSRect(x: ringX, y: inset, width: diameter, height: diameter)

        let track = NSBezierPath(ovalIn: ring.insetBy(dx: 1.5, dy: 1.5))
        NSColor.secondaryLabelColor.withAlphaComponent(0.3).setStroke()
        track.lineWidth = 3
        track.stroke()

        if progress > 0 {
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: ring.midX, y: ring.midY),
                          radius: diameter / 2 - 1.5,
                          startAngle: 90, endAngle: 90 - 360 * progress,
                          clockwise: true)
            NSColor.controlAccentColor.setStroke()
            arc.lineWidth = 3
            arc.lineCapStyle = .round
            arc.stroke()
        }

        guard !label.isEmpty else { return }
        var attrs = Self.captionAttributes
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        attrs[.paragraphStyle] = paragraph
        let textRect: NSRect
        if corner.isLeft {
            textRect = NSRect(x: ring.maxX + 8, y: (bounds.height - 16) / 2,
                              width: bounds.width - ring.maxX - 14, height: 16)
        } else {
            textRect = NSRect(x: 8, y: (bounds.height - 16) / 2,
                              width: ring.minX - 14, height: 16)
        }
        (label as NSString).draw(in: textRect, withAttributes: attrs)
    }
}

/// A soft radial glow anchored at the view corner that sits at the screen corner.
private final class CornerGlowView: NSView {
    private let corner: Corner
    init(corner: Corner) {
        self.corner = corner
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let center = CGPoint(x: corner.isLeft ? bounds.minX : bounds.maxX,
                             y: corner.isBottom ? bounds.minY : bounds.maxY)
        let base = NSColor.controlAccentColor.usingColorSpace(.sRGB)
            ?? NSColor(srgbRed: 0.0, green: 0.48, blue: 1.0, alpha: 1)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colors = [base.withAlphaComponent(0.5).cgColor,
                      base.withAlphaComponent(0.0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors,
                                        locations: [0, 1]) else { return }
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: bounds.width, options: [])
    }
}
