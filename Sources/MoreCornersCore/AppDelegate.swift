import AppKit
import Combine
import SwiftUI

/// Public entry point for the thin executable target. Retains the delegate
/// (NSApplication holds it weakly) and starts the run loop.
public enum MoreCornersApp {
    private static var delegate: AppDelegate?

    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

/// Restoring a persisted timed pause at launch. The deadline is stored in
/// UserDefaults (separate from the settings snapshot — it's transient state,
/// not configuration) because `enabled == false` *is* persisted: without this,
/// "pause for an hour" followed by a relaunch would be paused forever.
enum TimedPause {
    static let defaultsKey = "pausedUntil"

    enum Decision: Equatable {
        case none            // nothing pending (clear any stale stored deadline)
        case resume          // the deadline passed while the app wasn't running
        case rearm(Date)     // still pending — restore the deadline and timer
    }

    /// Pure — exposed for unit testing.
    static func decide(now: Date, until: Date?, enabled: Bool) -> Decision {
        guard let until, !enabled else { return .none }
        return until > now ? .rearm(until) : .resume
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem?
    private let monitor = CornerMonitor()
    private var settingsWindow: NSWindow?
    private var iconVisibilityCancellable: AnyCancellable?
    private var enabledCancellable: AnyCancellable?
    /// A pending timed pause: the timer that re-enables, and when it fires.
    private var pauseTimer: Timer?
    private var pausedUntil: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if SPARKLE
        SparkleUpdater.start()
        #endif

        if AppSettings.shared.showMenuBarIcon {
            installStatusItem()
        }
        // React to later toggles from Settings. dropFirst() skips the value the
        // @Published publisher emits synchronously on subscribe (already handled
        // above) so we only respond to real changes — and don't fire the
        // hidden-icon alert on every launch.
        iconVisibilityCancellable = AppSettings.shared.$showMenuBarIcon
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] visible in self?.setStatusItem(visible: visible) }

        // Keep the menu bar icon in step with the paused / keep-awake state, and
        // cancel any pending timed pause when hot corners are turned back on
        // (whether from the menu, Settings, or the auto-resume timer).
        enabledCancellable = AppSettings.shared.$enabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled { self.clearTimedPause() }
                // @Published emits on willSet, so AppSettings.shared.enabled
                // still holds the old value here — draw from the emitted one.
                self.setStatusIcon(paused: !enabled)
            }
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshStatusIcon),
            name: .keepAwakeChanged, object: nil)

        restoreTimedPause()
        monitor.start()

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didLaunchBefore") {
            defaults.set(true, forKey: "didLaunchBefore")
            openSettings()
        }
    }

    /// Re-launching the running app (Finder / Spotlight / Launchpad / `open`)
    /// reopens Settings. This is the way back when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows: Bool) -> Bool {
        openSettings()
        return true
    }

    // MARK: - Status item

    private func setStatusItem(visible: Bool) {
        if visible {
            if statusItem == nil { installStatusItem() }
        } else {
            removeStatusItem()
            explainHiddenIconIfNeeded()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
        refreshStatusIcon()
    }

    /// Redraws the menu bar icon for the current paused / keep-awake state.
    @objc private func refreshStatusIcon() {
        setStatusIcon(paused: !AppSettings.shared.enabled)
    }

    private func setStatusIcon(paused: Bool) {
        statusItem?.button?.image = Self.menuBarIcon(
            paused: paused,
            keepAwake: ActionRunner.keepAwakeOn)
    }

    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    /// The first time the icon is hidden, tell the user how to get Settings back
    /// — otherwise a hidden icon plus a closed window looks like the app vanished.
    private func explainHiddenIconIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didExplainHiddenIcon") else { return }
        defaults.set(true, forKey: "didExplainHiddenIcon")
        let alert = NSAlert()
        alert.messageText = "Menu bar icon hidden"
        alert.informativeText = """
            MoreCorners keeps running and your hot corners still work.

            To reopen this Settings window later, just launch MoreCorners again \
            from Finder, Spotlight, or Launchpad — the running app will bring \
            Settings back.
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = AppSettings.shared

        if settings.enabled {
            let pause = NSMenuItem(title: "Pause Hot Corners",
                                   action: #selector(pauseIndefinitely), keyEquivalent: "")
            pause.target = self
            menu.addItem(pause)

            let pauseFor = NSMenuItem(title: "Pause For", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for (title, minutes) in [("15 Minutes", 15), ("1 Hour", 60), ("2 Hours", 120)] {
                let item = NSMenuItem(title: title, action: #selector(pauseForMinutes(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = minutes
                submenu.addItem(item)
            }
            let tomorrow = NSMenuItem(title: "Until Tomorrow",
                                      action: #selector(pauseUntilTomorrow), keyEquivalent: "")
            tomorrow.target = self
            submenu.addItem(tomorrow)
            pauseFor.submenu = submenu
            menu.addItem(pauseFor)
        } else {
            var title = "Resume Hot Corners"
            if let until = pausedUntil {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                formatter.dateStyle = Calendar.current.isDateInToday(until) ? .none : .short
                title += " (paused until \(formatter.string(from: until)))"
            }
            let resume = NSMenuItem(title: title, action: #selector(resumeNow), keyEquivalent: "")
            resume.target = self
            menu.addItem(resume)
        }

        let awake = NSMenuItem(title: "Keep Mac Awake",
                               action: #selector(toggleAwake), keyEquivalent: "")
        awake.target = self
        awake.state = ActionRunner.keepAwakeOn ? .on : .off
        menu.addItem(awake)

        menu.addItem(.separator())

        for corner in Corner.allCases {
            let config = settings.config(for: corner)
            let baseLabel = config.base.action == .none && !config.variants.isEmpty
                ? "—" : config.base.action.label
            let item = NSMenuItem(title: "\(corner.label): \(baseLabel)",
                                  action: #selector(runMenuAction(_:)), keyEquivalent: "")
            if config.base.action != .none {
                item.target = self
                item.representedObject = config.base
                item.toolTip = "Run “\(config.base.action.label)” now"
            } else {
                item.isEnabled = false
            }
            menu.addItem(item)
            for variant in config.variants
            where variant.spec.action != .none && !variant.modifiers.isEmpty {
                let sub = NSMenuItem(
                    title: "      \(variant.modifiers.symbols)  \(variant.spec.action.label)",
                    action: #selector(runMenuAction(_:)), keyEquivalent: "")
                sub.target = self
                sub.representedObject = variant.spec
                sub.toolTip = "Run “\(variant.spec.action.label)” now"
                menu.addItem(sub)
            }
        }

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Settings…",
                               action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        #if SPARKLE
        menu.addItem(SparkleUpdater.shared.makeMenuItem())
        #endif

        let quit = NSMenuItem(title: "Quit MoreCorners",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func runMenuAction(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? ActionSpec else { return }
        ActionRunner.run(spec)
    }

    // MARK: - Pause / resume

    @objc private func pauseIndefinitely() {
        clearTimedPause()
        AppSettings.shared.enabled = false
    }

    @objc private func resumeNow() {
        // The $enabled observer clears any pending timed pause.
        AppSettings.shared.enabled = true
    }

    @objc private func pauseForMinutes(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        pause(until: Date().addingTimeInterval(TimeInterval(minutes * 60)))
    }

    @objc private func pauseUntilTomorrow() {
        // 9am tomorrow, or a 12-hour fallback if the calendar math fails.
        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1,
                                            to: calendar.startOfDay(for: Date()))
        let nineAM = startOfTomorrow.flatMap {
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0)
        }
        pause(until: nineAM ?? Date().addingTimeInterval(12 * 3600))
    }

    /// Pause hot corners until `date`, scheduling an auto-resume. The deadline
    /// is persisted so the pause stays *timed* across an app relaunch.
    private func pause(until date: Date) {
        pauseTimer?.invalidate()
        pausedUntil = date
        UserDefaults.standard.set(date, forKey: TimedPause.defaultsKey)
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in
            AppSettings.shared.enabled = true
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
        AppSettings.shared.enabled = false
    }

    /// Cancels any pending timed-pause auto-resume.
    private func clearTimedPause() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        pausedUntil = nil
        UserDefaults.standard.removeObject(forKey: TimedPause.defaultsKey)
    }

    /// Resolves a timed pause left over from the previous run: resume if its
    /// deadline has passed, otherwise restore the deadline and its timer.
    private func restoreTimedPause() {
        let stored = UserDefaults.standard.object(forKey: TimedPause.defaultsKey) as? Date
        switch TimedPause.decide(now: Date(), until: stored,
                                 enabled: AppSettings.shared.enabled) {
        case .none:
            UserDefaults.standard.removeObject(forKey: TimedPause.defaultsKey)
        case .resume:
            AppSettings.shared.enabled = true   // the $enabled observer cleans up
        case .rearm(let until):
            pause(until: until)
        }
    }

    @objc private func toggleAwake() {
        ActionRunner.toggleKeepAwake()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView())
            // Resize the window to whatever the current tab's content needs, so it
            // grows and shrinks as tabs are switched (each tab sets its own height).
            host.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: host)
            window.title = "MoreCorners"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu bar icon

    /// A monochrome template version of the app icon: four corner brackets
    /// with a pointer arrowing into the top-left corner. Drawn as a template
    /// image so it tints correctly for light/dark menu bars and selection.
    static func menuBarIcon(paused: Bool = false, keepAwake: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = size.width
            // Dim the whole mark when paused so a hidden/idle state reads at a
            // glance; the slash on top makes it unmistakable.
            let ink = NSColor.black.withAlphaComponent(paused ? 0.35 : 1.0).cgColor
            ctx.setStrokeColor(ink)
            ctx.setFillColor(ink)
            ctx.setLineWidth(s * 1.7 / 18)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let margin = s * 2.3 / 18
            let arm = s * 4.6 / 18
            let r = CGRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)

            func bracket(_ cx: CGFloat, _ cy: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
                ctx.move(to: CGPoint(x: cx + dx * arm, y: cy))
                ctx.addLine(to: CGPoint(x: cx, y: cy))
                ctx.addLine(to: CGPoint(x: cx, y: cy + dy * arm))
                ctx.strokePath()
            }
            bracket(r.minX, r.maxY, 1, -1)   // top-left
            bracket(r.maxX, r.maxY, -1, -1)  // top-right
            bracket(r.minX, r.minY, 1, 1)    // bottom-left
            bracket(r.maxX, r.minY, -1, 1)   // bottom-right

            // Pointer cursor, tip at origin, body down-right (y-down shape).
            let arrow: [CGPoint] = [
                CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 16.5), CGPoint(x: 4.6, y: 12.8),
                CGPoint(x: 7.4, y: 19.2), CGPoint(x: 10.0, y: 18.1),
                CGPoint(x: 7.3, y: 12.0), CGPoint(x: 12.7, y: 12.0),
            ]
            ctx.saveGState()
            let scale = s * 0.34 / 18
            ctx.translateBy(x: r.minX + s * 3.2 / 18, y: r.maxY - s * 3.2 / 18)
            ctx.scaleBy(x: scale, y: -scale)
            ctx.beginPath()
            ctx.addLines(between: arrow)
            ctx.closePath()
            ctx.fillPath()
            ctx.restoreGState()

            // Keep Awake: a small filled dot centered on the bottom edge.
            if keepAwake {
                ctx.setFillColor(NSColor.black.withAlphaComponent(paused ? 0.5 : 1).cgColor)
                let dotR = s * 2.0 / 18
                ctx.fillEllipse(in: CGRect(x: s / 2 - dotR, y: r.minY - dotR,
                                           width: dotR * 2, height: dotR * 2))
            }

            // Paused: a diagonal slash from top-left to bottom-right.
            if paused {
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.9).cgColor)
                ctx.setLineWidth(s * 1.9 / 18)
                ctx.setLineCap(.round)
                let inset = s * 2.6 / 18
                ctx.move(to: CGPoint(x: inset, y: s - inset))
                ctx.addLine(to: CGPoint(x: s - inset, y: inset))
                ctx.strokePath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
