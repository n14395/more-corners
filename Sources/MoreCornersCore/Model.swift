import AppKit
import Combine
import ServiceManagement

// MARK: - Corners

enum Corner: String, Codable, CaseIterable, Hashable {
    case topLeft, topRight, bottomLeft, bottomRight

    var label: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    var symbol: String {
        switch self {
        case .topLeft: return "arrow.up.left"
        case .topRight: return "arrow.up.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomRight: return "arrow.down.right"
        }
    }

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }
}

// MARK: - Modifier combinations

struct ModifierKeys: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let control = ModifierKeys(rawValue: 1 << 0)
    static let option = ModifierKeys(rawValue: 1 << 1)
    static let shift = ModifierKeys(rawValue: 1 << 2)
    static let command = ModifierKeys(rawValue: 1 << 3)

    init(rawValue: Int) { self.rawValue = rawValue }

    init(flags: NSEvent.ModifierFlags) {
        var keys: ModifierKeys = []
        if flags.contains(.control) { keys.insert(.control) }
        if flags.contains(.option) { keys.insert(.option) }
        if flags.contains(.shift) { keys.insert(.shift) }
        if flags.contains(.command) { keys.insert(.command) }
        self = keys
    }

    /// Standard macOS display order: ⌃ ⌥ ⇧ ⌘
    var symbols: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option) { s += "⌥" }
        if contains(.shift) { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

// MARK: - Actions

enum ActionGroup: String, CaseIterable {
    case windows = "Windows & Desktop"
    case power = "Display & Power"
    case media = "Sound & Media"
    case capture = "Capture"
    case system = "System"
    case custom = "Open & Run"

    var actions: [ActionType] {
        ActionType.allCases.filter { $0 != .none && $0.group == self }
    }
}

enum ActionType: String, Codable, CaseIterable, Hashable {
    case none

    // Windows & Desktop
    case missionControl, appExpose, showDesktop, launchpad
    case openControlCenter, openNotificationCenter, openAppleMenu, openQuickNote
    case nextSpace, previousSpace, moveWindowNextSpace, moveWindowPreviousSpace
    case hideFrontApp, hideOthers, quitFrontApp

    // Display & Power
    case lockScreen, screenSaver, displaySleep, systemSleep
    case toggleKeepAwake, brightnessUp, brightnessDown, logOut

    // Sound & Media
    case muteToggle, volumeUp, volumeDown, playPause, nextTrack, previousTrack

    // Capture
    case screenshotArea, screenshotFull

    // System
    case toggleDarkMode, toggleDockAutohide, emptyTrash

    // Open & Run
    case launchApp, openURL, openFileFolder, runShell, runAppleScript, runShortcut, pressKeys

    var group: ActionGroup {
        switch self {
        case .none, .missionControl, .appExpose, .showDesktop, .launchpad,
             .openControlCenter, .openNotificationCenter, .openAppleMenu, .openQuickNote,
             .nextSpace, .previousSpace, .moveWindowNextSpace, .moveWindowPreviousSpace,
             .hideFrontApp, .hideOthers, .quitFrontApp:
            return .windows
        case .lockScreen, .screenSaver, .displaySleep, .systemSleep,
             .toggleKeepAwake, .brightnessUp, .brightnessDown, .logOut:
            return .power
        case .muteToggle, .volumeUp, .volumeDown, .playPause, .nextTrack, .previousTrack:
            return .media
        case .screenshotArea, .screenshotFull:
            return .capture
        case .toggleDarkMode, .toggleDockAutohide, .emptyTrash:
            return .system
        case .launchApp, .openURL, .openFileFolder, .runShell, .runAppleScript,
             .runShortcut, .pressKeys:
            return .custom
        }
    }

    var label: String {
        switch self {
        case .none: return "None"
        case .missionControl: return "Mission Control"
        case .appExpose: return "Application Windows"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad / Apps"
        case .openControlCenter: return "Open Control Center"
        case .openNotificationCenter: return "Open Notification Center"
        case .openAppleMenu: return "Open Apple Menu"
        case .openQuickNote: return "Open Quick Note"
        case .nextSpace: return "Next Space"
        case .previousSpace: return "Previous Space"
        case .moveWindowNextSpace: return "Move App to Next Space"
        case .moveWindowPreviousSpace: return "Move App to Previous Space"
        case .hideFrontApp: return "Hide Frontmost App"
        case .hideOthers: return "Hide All Other Apps"
        case .quitFrontApp: return "Quit Frontmost App"
        case .lockScreen: return "Lock Screen"
        case .screenSaver: return "Start Screen Saver"
        case .displaySleep: return "Put Display to Sleep"
        case .systemSleep: return "Put Mac to Sleep"
        case .toggleKeepAwake: return "Toggle Keep Awake"
        case .brightnessUp: return "Brightness Up"
        case .brightnessDown: return "Brightness Down"
        case .logOut: return "Log Out…"
        case .muteToggle: return "Toggle Mute"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .playPause: return "Play / Pause"
        case .nextTrack: return "Next Track"
        case .previousTrack: return "Previous Track"
        case .screenshotArea: return "Screenshot Area → Clipboard"
        case .screenshotFull: return "Screenshot Screen → Desktop"
        case .toggleDarkMode: return "Toggle Dark Mode"
        case .toggleDockAutohide: return "Toggle Dock Auto-Hide"
        case .emptyTrash: return "Empty Trash"
        case .launchApp: return "Launch App…"
        case .openURL: return "Open URL…"
        case .openFileFolder: return "Open File / Folder…"
        case .runShell: return "Run Shell Command…"
        case .runAppleScript: return "Run AppleScript…"
        case .runShortcut: return "Run Shortcuts Shortcut…"
        case .pressKeys: return "Press Keyboard Shortcut…"
        }
    }

    var needsParameter: Bool {
        switch self {
        case .launchApp, .openURL, .openFileFolder, .runShell, .runAppleScript,
             .runShortcut, .pressKeys:
            return true
        default:
            return false
        }
    }

    var usesFilePicker: Bool {
        self == .launchApp || self == .openFileFolder
    }

    var parameterPlaceholder: String {
        switch self {
        case .launchApp: return "/Applications/Safari.app"
        case .openURL: return "https://example.com"
        case .openFileFolder: return "/Users/you/Documents"
        case .runShell: return "say \"hello\""
        case .runAppleScript: return "display dialog \"Hi\"  (or path to .scpt)"
        case .runShortcut: return "Shortcut name"
        case .pressKeys: return "cmd+shift+4  (or ctrl+left, f11, …)"
        default: return ""
        }
    }

    /// Actions that require the Accessibility permission (they synthesize HID events).
    var needsAccessibility: Bool {
        switch self {
        case .brightnessUp, .brightnessDown, .playPause, .nextTrack, .previousTrack,
             .pressKeys, .openControlCenter, .openNotificationCenter,
             .openAppleMenu, .openQuickNote,
             .nextSpace, .previousSpace, .moveWindowNextSpace, .moveWindowPreviousSpace:
            return true
        default:
            return false
        }
    }
}

// MARK: - Per-corner config

struct ActionSpec: Codable, Hashable {
    var action: ActionType = .none
    var parameter: String = ""
}

struct CornerConfig: Codable, Hashable {
    /// Runs when no modifier override matches the held modifiers.
    var base: ActionSpec = ActionSpec()
    /// Alternate actions, each bound to an exact modifier combination.
    var variants: [Variant] = []
    /// When off, the corner keeps its configuration but never fires on its own
    /// (the ▶ test buttons still work).
    var enabled: Bool = true

    struct Variant: Codable, Hashable, Identifiable {
        var id = UUID()
        var modifiers: ModifierKeys = []
        var spec: ActionSpec = ActionSpec()
    }

    init(base: ActionSpec = ActionSpec(), variants: [Variant] = [], enabled: Bool = true) {
        self.base = base
        self.variants = variants
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey { case base, variants, enabled }

    // Custom decode so blobs written before `enabled` existed still load — a missing
    // key would otherwise fail the whole settings decode and wipe the user's config.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = try c.decodeIfPresent(ActionSpec.self, forKey: .base) ?? ActionSpec()
        variants = try c.decodeIfPresent([Variant].self, forKey: .variants) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// The spec to run for a given set of held modifiers, or nil to keep waiting
    /// (nothing matches yet, but an override could once modifiers change).
    func resolve(held: ModifierKeys) -> ActionSpec? {
        if let variant = variants.first(where: {
            !$0.modifiers.isEmpty && $0.modifiers == held && $0.spec.action != .none
        }) {
            return variant.spec
        }
        if base.action != .none { return base }
        return nil
    }

    var isConfigured: Bool {
        base.action != .none || variants.contains { $0.spec.action != .none }
    }
}

// MARK: - Exclusions

/// An app that suppresses hot corners while it's frontmost, identified by bundle
/// ID (the name is kept only for display).
struct ExcludedApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

// MARK: - Settings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var corners: [Corner: CornerConfig] = [:]
    @Published var dwell: Double = 0.25
    @Published var cornerSize: Double = 6
    @Published var allScreens = true
    @Published var enabled = true
    @Published var launchAtLogin = false
    @Published var showMenuBarIcon = true
    /// Suppress hot corners while the frontmost window is full-screen.
    @Published var suppressInFullScreen = false
    /// Apps that suppress hot corners while frontmost.
    @Published var excludedApps: [ExcludedApp] = []
    /// Trigger feedback when a corner action fires.
    @Published var feedbackFlash = false
    @Published var feedbackSound = false
    @Published var feedbackHaptic = false
    @Published var feedbackSoundName = "Tink"
    /// Fire the instant the pointer reaches the very corner (no dwell, tiny
    /// zone) rather than dwelling inside a `cornerSize` zone. Ignores `dwell`
    /// and `cornerSize`.
    @Published var slamToActivate = false

    private struct Snapshot: Codable {
        var corners: [Corner: CornerConfig]
        var dwell: Double
        var cornerSize: Double
        var allScreens: Bool
        var enabled: Bool
        // Fields added after v2 shipped: absent in older blobs, so decode as
        // optional and fall back to a default (see `apply`).
        var showMenuBarIcon: Bool?
        var suppressInFullScreen: Bool?
        var excludedApps: [ExcludedApp]?
        var feedbackFlash: Bool?
        var feedbackSound: Bool?
        var feedbackHaptic: Bool?
        var feedbackSoundName: String?
        var slamToActivate: Bool?
    }

    // v1 stored a single action + modifier requirement per corner.
    private struct LegacyCornerConfig: Codable {
        var action: ActionType
        var modifier: String
        var parameter: String
    }

    private struct LegacySnapshot: Codable {
        var corners: [Corner: LegacyCornerConfig]
        var dwell: Double
        var cornerSize: Double
        var allScreens: Bool
        var enabled: Bool
    }

    private static let defaultsKey = "settings.v2"
    private static let legacyKey = "settings.v1"
    private var saveCancellable: AnyCancellable?

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.defaultsKey),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            apply(snap)
        } else if let data = defaults.data(forKey: Self.legacyKey),
                  let migrated = Self.migrateLegacyData(data) {
            corners = migrated.corners
            dwell = migrated.dwell
            cornerSize = migrated.cornerSize
            allScreens = migrated.allScreens
            enabled = migrated.enabled
            defaults.removeObject(forKey: Self.legacyKey)
            save()
        } else {
            // Fresh install: start from the built-in default layout rather than
            // an empty grid, so the app does something useful out of the box.
            apply(Self.factoryDefaultSnapshot())
            save()
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        saveCancellable = objectWillChange
            .debounce(for: .seconds(0.25), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
    }

    /// The result of migrating a v1 settings blob to the current model.
    struct MigratedSettings: Equatable {
        var corners: [Corner: CornerConfig]
        var dwell: Double
        var cornerSize: Double
        var allScreens: Bool
        var enabled: Bool
    }

    /// Decodes a v1 (`settings.v1`) blob and maps it onto the current model:
    /// a corner's old modifier requirement becomes either its default action
    /// ("any"/"plain") or a single modifier override (⌘/⌥/⌃/⇧). Returns nil if
    /// the data isn't a valid v1 snapshot. Pure — exposed for unit testing.
    static func migrateLegacyData(_ data: Data) -> MigratedSettings? {
        guard let old = try? JSONDecoder().decode(LegacySnapshot.self, from: data) else {
            return nil
        }
        var corners: [Corner: CornerConfig] = [:]
        for (corner, legacy) in old.corners {
            var config = CornerConfig()
            let spec = ActionSpec(action: legacy.action, parameter: legacy.parameter)
            let modifier: ModifierKeys?
            switch legacy.modifier {
            case "command": modifier = .command
            case "option": modifier = .option
            case "control": modifier = .control
            case "shift": modifier = .shift
            default: modifier = nil // "any" / "plain" become the default action
            }
            if let modifier {
                config.variants = [CornerConfig.Variant(modifiers: modifier, spec: spec)]
            } else {
                config.base = spec
            }
            corners[corner] = config
        }
        return MigratedSettings(corners: corners, dwell: old.dwell,
                                cornerSize: old.cornerSize, allScreens: old.allScreens,
                                enabled: old.enabled)
    }

    func config(for corner: Corner) -> CornerConfig {
        corners[corner] ?? CornerConfig()
    }

    /// Whether hot corners are suppressed for a frontmost app. Pure — for testing.
    func excludes(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedApps.contains { $0.bundleID == bundleID }
    }

    /// The suppression decision at fire time. `isFullScreen` is the live state
    /// CornerMonitor supplies (only queried when `suppressInFullScreen` is on).
    /// Pure — exposed for unit testing.
    func shouldSuppress(frontmostBundleID: String?, isFullScreen: Bool) -> Bool {
        if suppressInFullScreen && isFullScreen { return true }
        return excludes(bundleID: frontmostBundleID)
    }

    private func currentSnapshot() -> Snapshot {
        Snapshot(corners: corners, dwell: dwell, cornerSize: cornerSize,
                 allScreens: allScreens, enabled: enabled, showMenuBarIcon: showMenuBarIcon,
                 suppressInFullScreen: suppressInFullScreen, excludedApps: excludedApps,
                 feedbackFlash: feedbackFlash, feedbackSound: feedbackSound,
                 feedbackHaptic: feedbackHaptic, feedbackSoundName: feedbackSoundName,
                 slamToActivate: slamToActivate)
    }

    /// The built-in default configuration. This is the layout a fresh install
    /// starts with and the one "Reset to Defaults" restores: hot corners for the
    /// menu bar / spaces on the top corners, Quick Note and Show Desktop below.
    private static func factoryDefaultSnapshot() -> Snapshot {
        func variant(_ mods: ModifierKeys, _ action: ActionType) -> CornerConfig.Variant {
            CornerConfig.Variant(modifiers: mods, spec: ActionSpec(action: action))
        }
        let corners: [Corner: CornerConfig] = [
            .topLeft: CornerConfig(
                base: ActionSpec(action: .openAppleMenu),
                variants: [variant(.control, .previousSpace),
                           variant(.option, .moveWindowPreviousSpace)]),
            .topRight: CornerConfig(
                base: ActionSpec(action: .openNotificationCenter),
                variants: [variant(.control, .nextSpace),
                           variant(.option, .moveWindowNextSpace)]),
            .bottomLeft: CornerConfig(base: ActionSpec(action: .openQuickNote)),
            .bottomRight: CornerConfig(base: ActionSpec(action: .showDesktop)),
        ]
        return Snapshot(
            corners: corners, dwell: 0.05, cornerSize: 16, allScreens: true,
            enabled: true, showMenuBarIcon: true, suppressInFullScreen: false,
            excludedApps: [], feedbackFlash: true, feedbackSound: false,
            feedbackHaptic: true, feedbackSoundName: "Purr", slamToActivate: false)
    }

    /// Replace all settings (corners and preferences) with the built-in defaults.
    func resetToDefaults() {
        apply(Self.factoryDefaultSnapshot())
        save()
    }

    private func apply(_ snap: Snapshot) {
        corners = snap.corners
        dwell = snap.dwell
        cornerSize = snap.cornerSize
        allScreens = snap.allScreens
        enabled = snap.enabled
        showMenuBarIcon = snap.showMenuBarIcon ?? true
        suppressInFullScreen = snap.suppressInFullScreen ?? false
        excludedApps = snap.excludedApps ?? []
        feedbackFlash = snap.feedbackFlash ?? false
        feedbackSound = snap.feedbackSound ?? false
        feedbackHaptic = snap.feedbackHaptic ?? false
        feedbackSoundName = snap.feedbackSoundName ?? "Tink"
        slamToActivate = snap.slamToActivate ?? false
    }

    /// Pretty-printed JSON of all settings, for the Export button.
    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(currentSnapshot())
    }

    /// Replace all settings from an exported JSON blob (Import button). Returns
    /// false if the data isn't a valid settings file.
    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return false }
        apply(snap)
        save()
        return true
    }

    /// System alert sounds available for trigger feedback.
    static var availableSoundNames: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds"))?
            .compactMap { $0.hasSuffix(".aiff") ? String($0.dropLast(5)) : nil }
            .sorted() ?? ["Tink"]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(currentSnapshot()) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func applyLaunchAtLogin(_ on: Bool) {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else {
            NSLog("Launch at login requires running from the .app bundle")
            return
        }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at login change failed: \(error)")
        }
    }
}
