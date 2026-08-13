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
