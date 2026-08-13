import AppKit
import ApplicationServices
import Darwin
import IOKit.pwr_mgt

/// A borderless window that can become key, used to pull keyboard focus
/// (and with it the "active display") onto a target screen.
private final class FocusGrabWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

extension Notification.Name {
    /// Posted whenever Keep Awake is toggled, so the menu bar icon can update.
    static let keepAwakeChanged = Notification.Name("dev.nwf.MoreCorners.keepAwakeChanged")
}

enum ActionRunner {

    static func run(_ spec: ActionSpec) {
        let param = spec.parameter.trimmingCharacters(in: .whitespacesAndNewlines)
        switch spec.action {
        case .none:
            break

        // MARK: Windows & Desktop
        // These use CoreDock notifications — the mechanism the Dock itself
        // listens on — which stays working across macOS releases (unlike the
        // moved Mission Control binary or synthesized ⌃-arrow shortcuts).
        case .missionControl: coreDock("com.apple.expose.awake")
        case .showDesktop: coreDock("com.apple.showdesktop.awake")
        case .appExpose: coreDock("com.apple.expose.front.awake")
        case .launchpad: openLaunchpad()
        case .nextSpace: SpaceControl.switchSpace(next: true)
        case .previousSpace: SpaceControl.switchSpace(next: false)
        case .moveWindowNextSpace: SpaceControl.moveFocusedWindow(next: true)
        case .moveWindowPreviousSpace: SpaceControl.moveFocusedWindow(next: false)
        case .openControlCenter:
            pressMenuExtra(identifierSuffix: "menuextra.controlcenter")
        case .openNotificationCenter:
            // fn+N opens Notification Center on the active display; the
            // focus grab moves the active display to the pointer's first.
            guard checkAccessibility() else { return }
            withPointerDisplayFocused { postKeystroke(45, flags: .maskSecondaryFn) }
        case .openAppleMenu: openAppleMenu()
        case .openQuickNote:
            // The system-wide Quick Note globe shortcut (fn+Q, on by default in
            // System Settings → Keyboard → "Press 🌐 key").
            guard checkAccessibility() else { return }
            withPointerDisplayFocused { postKeystroke(12, flags: .maskSecondaryFn) }
        case .hideFrontApp:
            NSWorkspace.shared.frontmostApplication?.hide()
        case .hideOthers:
            let front = NSWorkspace.shared.frontmostApplication
            for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && app != front {
                app.hide()
            }
        case .quitFrontApp:
            if let front = NSWorkspace.shared.frontmostApplication,
               front.bundleIdentifier != "com.apple.finder",
               front != NSRunningApplication.current {
                front.terminate()
            }

        // MARK: Display & Power
        case .lockScreen: lockScreen()
        case .screenSaver:
            openApp(at: "/System/Library/CoreServices/ScreenSaverEngine.app")
        case .displaySleep: shell("/usr/bin/pmset", ["displaysleepnow"])
        case .systemSleep: shell("/usr/bin/pmset", ["sleepnow"])
        case .toggleKeepAwake: toggleKeepAwake()
        case .brightnessUp: postSystemKey(2)   // NX_KEYTYPE_BRIGHTNESS_UP
        case .brightnessDown: postSystemKey(3) // NX_KEYTYPE_BRIGHTNESS_DOWN
        case .logOut:
            appleScript("tell application \"System Events\" to log out")

        // MARK: Sound & Media
        case .muteToggle:
            appleScript("set volume output muted (not (output muted of (get volume settings)))")
        case .volumeUp:
            appleScript("set volume output volume (((output volume of (get volume settings)) + 7) as integer)")
        case .volumeDown:
            appleScript("set volume output volume (((output volume of (get volume settings)) - 7) as integer)")
        case .playPause: postSystemKey(16)     // NX_KEYTYPE_PLAY
        case .nextTrack: postSystemKey(19)     // NX_KEYTYPE_FAST
        case .previousTrack: postSystemKey(20) // NX_KEYTYPE_REWIND

        // MARK: Capture
        case .screenshotArea:
            shell("/usr/sbin/screencapture", ["-i", "-c"])
        case .screenshotFull:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let name = "Screenshot \(formatter.string(from: Date())).png"
            let path = (NSHomeDirectory() as NSString).appendingPathComponent("Desktop/\(name)")
            shell("/usr/sbin/screencapture", [path])

        // MARK: System
        case .toggleDarkMode:
            appleScript("""
                tell application "System Events" to tell appearance preferences to \
                set dark mode to not dark mode
                """)
        case .toggleDockAutohide:
            shellCommand("""
                if [ "$(defaults read com.apple.dock autohide 2>/dev/null)" = "1" ]; then \
                defaults write com.apple.dock autohide -bool false; else \
                defaults write com.apple.dock autohide -bool true; fi; killall Dock
                """)
        case .emptyTrash:
            appleScript("tell application \"Finder\" to empty trash")

        // MARK: Open & Run
        case .launchApp:
            guard !param.isEmpty else { return }
            if param.hasPrefix("/") {
                openApp(at: param)
            } else {
                shell("/usr/bin/open", ["-a", param])
            }
        case .openURL:
            if let url = Self.normalizedURL(from: param) { NSWorkspace.shared.open(url) }
        case .openFileFolder:
            guard !param.isEmpty else { return }
            shell("/usr/bin/open", [(param as NSString).expandingTildeInPath])
        case .runShell:
            guard !param.isEmpty else { return }
            shellCommand(param)
        case .runAppleScript:
            guard !param.isEmpty else { return }
            if param.hasPrefix("/") || param.hasPrefix("~") {
                shell("/usr/bin/osascript", [(param as NSString).expandingTildeInPath])
            } else {
                appleScript(param)
            }
        case .runShortcut:
            guard !param.isEmpty else { return }
            shell("/usr/bin/shortcuts", ["run", param])
        case .pressKeys:
            guard !param.isEmpty else { return }
            pressKeys(param)
        }
    }

    // MARK: - Keep awake

    private static var awakeAssertion: IOPMAssertionID = 0
    private(set) static var keepAwakeOn = false

    static func toggleKeepAwake() {
        if keepAwakeOn {
            IOPMAssertionRelease(awakeAssertion)
            keepAwakeOn = false
        } else {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "MoreCorners Keep Awake" as CFString,
                &awakeAssertion)
            keepAwakeOn = result == kIOReturnSuccess
        }
        NotificationCenter.default.post(name: .keepAwakeChanged, object: nil)
    }

    /// Turns user-entered URL text into an openable URL, defaulting a missing
    /// scheme to https so bare hosts like "example.com" work. Returns nil for
    /// empty input. Pure and side-effect free — exposed for unit testing.
    static func normalizedURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://" + trimmed)
    }

    // MARK: - Helpers

    /// Sends a Dock notification via the private `CoreDockSendNotification`
    /// (exported by HIToolbox, which every Cocoa app already loads). Drives
    /// Mission Control, App Exposé, and Show Desktop the way the Dock does.
    private static func coreDock(_ notification: String) {
        typealias SendFunc = @convention(c) (CFString, Int32) -> Void
        guard let handle = dlopen(
            "/System/Library/Frameworks/Carbon.framework/Frameworks/HIToolbox.framework/HIToolbox",
            RTLD_NOW), let sym = dlsym(handle, "CoreDockSendNotification") else {
            NSLog("CoreDockSendNotification unavailable")
            return
        }
        unsafeBitCast(sym, to: SendFunc.self)(notification as CFString, 0)
    }

    private static func openLaunchpad() {
        let workspace = NSWorkspace.shared
        // Launchpad exists through macOS 15; macOS 26 replaced it with the
        // "Apps" launcher (com.apple.apps.launcher, /System/Applications/Apps.app).
        if workspace.urlForApplication(
            withBundleIdentifier: "com.apple.launchpad.launcher") != nil {
            coreDock("com.apple.launchpad.toggle")
        } else if let apps = workspace.urlForApplication(
            withBundleIdentifier: "com.apple.apps.launcher") {
            workspace.openApplication(at: apps, configuration: .init())
        } else {
            workspace.open(URL(fileURLWithPath: "/Applications"))
        }
    }

    private static func openApp(at path: String) {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
    }

    private static func lockScreen() {
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
            let sym = dlsym(handle, "SACLockScreenImmediate") else {
            NSLog("Lock screen unavailable")
            return
        }
        typealias LockFunc = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: LockFunc.self)()
    }

    private static func shell(_ path: String, _ args: [String]) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try Process.run(URL(fileURLWithPath: path), arguments: args)
            } catch {
                NSLog("Failed to run \(path): \(error)")
            }
        }
    }

    private static func shellCommand(_ command: String) {
        shell("/bin/zsh", ["-lc", command])
    }

    private static func appleScript(_ source: String) {
        shell("/usr/bin/osascript", ["-e", source])
    }

    // MARK: - Menu bar UI via Accessibility

    /// Presses one of the menu bar items hosted by the Control Center process
    /// (the Control Center "bento box", the clock that opens Notification
    /// Center, battery, Wi-Fi, …), found by AX identifier or description.
    /// Opens a system-owned menu extra (e.g. Control Center) by locating it
    /// through system-wide hit-testing and pressing it.
    ///
    /// On recent macOS the Control Center process exposes an empty AX tree, so
    /// reading its menu bar children fails. Hit-testing the menu bar via the
    /// system-wide element still finds the item, and scanning the menu bar of
    /// the *pointer's* display opens the panel on the right screen.
    private static func pressMenuExtra(identifierSuffix: String) {
        guard checkAccessibility() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let pointer = CGEvent(source: nil)?.location ?? .zero
            let displays = activeDisplayBounds()
            let display = displays.first { $0.insetBy(dx: -1, dy: -1).contains(pointer) }
                ?? displays.first ?? NSScreen.main?.frame ?? .zero

            let system = AXUIElementCreateSystemWide()
            let scanY = Float(display.minY + 12)   // menu bar sits at the display's top edge
            var x = Float(display.maxX) - 4
            let leftLimit = Float(display.maxX) - 700
            while x > leftLimit {
                var element: AXUIElement?
                if AXUIElementCopyElementAtPosition(system, x, scanY, &element) == .success,
                   let element,
                   let id = axValue(element, kAXIdentifierAttribute as String) as? String,
                   id.hasSuffix(identifierSuffix) {
                    AXUIElementPerformAction(element, kAXPressAction as CFString)
                    return
                }
                x -= 6
            }
            NSLog("Menu extra \(identifierSuffix) not found in the menu bar")
        }
    }

    /// Opens the Apple menu of the frontmost application's menu bar.
    private static func openAppleMenu() {
        guard checkAccessibility() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let front = NSWorkspace.shared.frontmostApplication else { return }
            let ax = AXUIElementCreateApplication(front.processIdentifier)
            guard let bar = axElement(ax, kAXMenuBarAttribute as String),
                  let items = axValue(bar, kAXChildrenAttribute as String) as? [AXUIElement],
                  let appleMenu = items.first else {
                NSLog("Menu bar of \(front.localizedName ?? "app") not accessible")
                return
            }
            pressMenuBarItem(appleMenu, alignedRight: false)
        }
    }

    /// Presses a menu bar element so its UI opens on the display the pointer
    /// is on. Menu bar panels normally open on the *focused* display, so when
    /// the pointer (i.e. the triggered corner) is on a different display, we
    /// click the equivalent spot in that display's own menu bar instead —
    /// menu extras are laid out right-aligned identically on every display,
    /// and the Apple menu is left-aligned. Falls back to a plain AX press
    /// when displays don't have separate menu bars.
    private static func pressMenuBarItem(_ element: AXUIElement, alignedRight: Bool) {
        func plainPress() { AXUIElementPerformAction(element, kAXPressAction as CFString) }

        guard NSScreen.screensHaveSeparateSpaces, let itemFrame = axFrame(element) else {
            plainPress()
            return
        }
        let itemCenter = CGPoint(x: itemFrame.midX, y: itemFrame.midY)
        let pointer = CGEvent(source: nil)?.location ?? .zero
        let displays = activeDisplayBounds()
        guard let pointerDisplay = displays.first(where: { $0.contains(pointer) }),
              let itemDisplay = displays.first(where: { $0.contains(itemCenter) }),
              !pointerDisplay.equalTo(itemDisplay) else {
            plainPress()
            return
        }
        let x = alignedRight
            ? pointerDisplay.maxX - (itemDisplay.maxX - itemCenter.x)
            : pointerDisplay.minX + (itemCenter.x - itemDisplay.minX)
        // CG coordinates have y growing downward, so minY is the menu bar edge.
        let click = CGPoint(x: x, y: pointerDisplay.minY + 12)
        synthesizeClick(at: click, restoringPointerTo: pointer)
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let posRef = axValue(element, kAXPositionAttribute as String),
              let sizeRef = axValue(element, kAXSizeAttribute as String),
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return (0..<Int(count)).map { CGDisplayBounds(ids[$0]) }
    }

    private static func synthesizeClick(at point: CGPoint, restoringPointerTo original: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        usleep(50_000)
        // Restore just outside any corner zone, so a corner-triggered action that
        // warps here and back doesn't immediately re-fire the corner.
        CGWarpMouseCursorPosition(CornerMonitor.restorePointClearOfCornerZones(original))
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return err == .success ? value : nil
    }

    private static func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = axValue(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    // MARK: - Focusing the pointer's display

    private static var focusGrabWindow: NSWindow?

    /// Runs `fire` with keyboard focus — and therefore the "active display" —
    /// on the display the pointer is on. Globe shortcuts (fn+N, fn+Q) open
    /// their UI on the active display, so when the triggered corner is on a
    /// different display we briefly key an invisible 2×2pt window there
    /// first, which pulls the active display over without clicking anything.
    private static func withPointerDisplayFocused(_ fire: @escaping () -> Void) {
        DispatchQueue.main.async {
            let pointerScreen = NSScreen.screens.first {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            }
            guard NSScreen.screens.count > 1,
                  NSScreen.screensHaveSeparateSpaces,
                  let target = pointerScreen,
                  target != activeDisplayScreen() else {
                fire()
                return
            }
            let frame = NSRect(x: target.frame.midX - 5, y: target.frame.midY - 5,
                               width: 10, height: 10)
            let window = FocusGrabWindow(contentRect: frame, styleMask: .borderless,
                                         backing: .buffered, defer: false)
            window.level = .floating
            window.backgroundColor = .clear
            window.alphaValue = 0.01
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.transient, .ignoresCycle, .canJoinAllSpaces]
            focusGrabWindow?.close()
            focusGrabWindow = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Programmatic activation of an accessory app does NOT move the
            // system's "active display" — only user interaction does. So
            // synthesize a click that lands on our own invisible window:
            // nothing else receives it, but it counts as interaction on the
            // target display and pulls the active display over for real.
            let pointer = CGEvent(source: nil)?.location ?? .zero
            let primaryTop = NSScreen.screens[0].frame.maxY
            let selfClick = CGPoint(x: window.frame.midX,
                                    y: primaryTop - window.frame.midY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                synthesizeClick(at: selfClick, restoringPointerTo: pointer)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    fire()
                    // Leave the window up briefly so the shortcut lands while
                    // the display is still active, then clean up. Focus is not
                    // handed back automatically: re-activating the previous
                    // app would dismiss the panel that just opened.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        window.close()
                        if focusGrabWindow === window { focusGrabWindow = nil }
                    }
                }
            }
        }
    }

    /// The display whose window currently has keyboard focus, found via the
    /// frontmost app's focused window (AX position is in CG coordinates).
    private static func activeDisplayScreen() -> NSScreen? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let ax = AXUIElementCreateApplication(front.processIdentifier)
        guard let windowRef = axValue(ax, kAXFocusedWindowAttribute as String),
              CFGetTypeID(windowRef) == AXUIElementGetTypeID(),
              let frame = axFrame(windowRef as! AXUIElement) else { return nil }
        let primaryTop = NSScreen.screens[0].frame.maxY
        let center = NSPoint(x: frame.midX, y: primaryTop - frame.midY)
        return NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
    }

    // MARK: - Synthetic events (need Accessibility)

    private static func checkAccessibility() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    /// Posts an NX system-defined key (media, brightness) press + release.
    private static func postSystemKey(_ key: Int32) {
        guard checkAccessibility() else { return }
        func post(down: Bool) {
            let data1 = Int((Int32(key) << 16) | Int32((down ? 0x0a : 0x0b) << 8))
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    private static func pressKeys(_ spec: String) {
        guard checkAccessibility() else { return }
        guard let (code, flags) = Self.parseKeySpec(spec) else { return }
        postKeystroke(code, flags: flags)
    }

    /// Parses a key spec such as "cmd+shift+4" or "ctrl left" into a virtual
    /// key code and modifier flags. Returns nil when no key token resolves.
    /// Pure and side-effect free — exposed for unit testing.
    static func parseKeySpec(_ spec: String) -> (CGKeyCode, CGEventFlags)? {
        var flags: CGEventFlags = []
        var keyCode: CGKeyCode?
        let tokens = spec.lowercased().split { $0 == "+" || $0.isWhitespace }
        for token in tokens.map(String.init) {
            switch token {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "shift", "⇧": flags.insert(.maskShift)
            case "fn": flags.insert(.maskSecondaryFn)
            default:
                keyCode = Self.keyCodes[token]
                if keyCode == nil { NSLog("Unknown key token: \(token)") }
            }
        }
        guard let code = keyCode else { return nil }
        return (code, flags)
    }

    /// Decodes one entry of an AppleSymbolicHotKeys dictionary into a key code
    /// and flags. Returns nil when the entry is missing, disabled, or
    /// malformed. Pure — exposed for unit testing.
    static func parseSymbolicHotkey(id: Int, from all: [String: Any])
        -> (CGKeyCode, CGEventFlags)? {
        guard let entry = all["\(id)"] as? [String: Any] else { return nil }
        let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false
        guard enabled,
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Any], params.count >= 3,
              let keyCode = (params[1] as? NSNumber)?.intValue, keyCode >= 0,
              let mods = (params[2] as? NSNumber)?.intValue else { return nil }
        var flags: CGEventFlags = []
        if mods & 131_072 != 0 { flags.insert(.maskShift) }
        if mods & 262_144 != 0 { flags.insert(.maskControl) }
        if mods & 524_288 != 0 { flags.insert(.maskAlternate) }
        if mods & 1_048_576 != 0 { flags.insert(.maskCommand) }
        if mods & 8_388_608 != 0 { flags.insert(.maskSecondaryFn) }
        return (CGKeyCode(keyCode), flags)
    }

    private static func postKeystroke(_ code: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// US-ANSI virtual key codes.
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8,
        "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25,
        "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33,
        "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
        ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
        "backspace": 51, "esc": 53, "escape": 53, "forwarddelete": 117,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79,
        "f19": 80, "f20": 90,
    ]
}
