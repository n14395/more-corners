import XCTest
import AppKit
@testable import MoreCornersCore

/// One entry per assignable action, describing how the E2E harness should
/// fire and (where possible) verify it.
struct ActionTestCase {
    let type: ActionType
    var parameter: String = ""
    /// Fires system-disruptive UI (lock, sleep, logout, quit, hide, trash);
    /// only run when MORECORNERS_E2E_DESTRUCTIVE=1.
    var destructive: Bool = false
    /// Opens blocking/interactive UI (e.g. screenshot selection); never fired,
    /// always listed for manual verification.
    var interactiveNoFire: Bool = false
    /// Returns false to skip (e.g. Screen Recording not granted).
    var precondition: (() -> Bool)?
    /// Capture "before" state.
    var setUp: (() -> Void)?
    /// Return whether the effect was observed. nil ⇒ not auto-observable
    /// (recorded on the manual checklist instead).
    var observe: (() -> Bool)?
    /// Restore any state the action changed.
    var tearDown: (() -> Void)?
}

/// A mutable holder so a case's `setUp` can stash a value its `observe`/
/// `tearDown` read back.
final class Box<T> {
    var value: T?
}

extension ActionIntegrationTests {

    static func makeCases() -> [ActionTestCase] {
        var cases: [ActionTestCase] = []

        // MARK: Windows & Desktop (effects not observable via public API)
        cases += [
            ActionTestCase(type: .missionControl),
            ActionTestCase(type: .appExpose),
            ActionTestCase(type: .showDesktop),
            ActionTestCase(type: .launchpad),
            ActionTestCase(type: .openControlCenter),
            ActionTestCase(type: .openNotificationCenter),
            ActionTestCase(type: .openAppleMenu),
            ActionTestCase(type: .openQuickNote),
            ActionTestCase(type: .nextSpace),
            ActionTestCase(type: .previousSpace),
            ActionTestCase(type: .moveWindowNextSpace, destructive: true),
            ActionTestCase(type: .moveWindowPreviousSpace, destructive: true),
            ActionTestCase(type: .hideFrontApp, destructive: true),
            ActionTestCase(type: .hideOthers, destructive: true),
            ActionTestCase(type: .quitFrontApp, destructive: true),
        ]

        // MARK: Display & Power
        let keepAwake = Box<Bool>()
        cases += [
            ActionTestCase(type: .lockScreen, destructive: true),
            ActionTestCase(type: .screenSaver, destructive: true),
            ActionTestCase(type: .displaySleep, destructive: true),
            ActionTestCase(type: .systemSleep, destructive: true),
            ActionTestCase(
                type: .toggleKeepAwake,
                setUp: { keepAwake.value = ActionRunner.keepAwakeOn },
                observe: { ActionRunner.keepAwakeOn != (keepAwake.value ?? false) },
                tearDown: {
                    if ActionRunner.keepAwakeOn != (keepAwake.value ?? false) {
                        ActionRunner.toggleKeepAwake()
                    }
                }),
            ActionTestCase(type: .brightnessUp),
            ActionTestCase(type: .brightnessDown),
            ActionTestCase(type: .logOut, destructive: true),
        ]

        // MARK: Sound & Media
        let muted = Box<Bool>()
        let volUp = Box<Int>()
        let volDown = Box<Int>()
        cases += [
            ActionTestCase(
                type: .muteToggle,
                setUp: { muted.value = readMuted() },
                observe: { readMuted() != (muted.value ?? false) },
                tearDown: { setMuted(muted.value ?? false) }),
            ActionTestCase(
                type: .volumeUp,
                setUp: { volUp.value = readVolume() },
                observe: { readVolume() >= (volUp.value ?? 0) },
                tearDown: { setVolume(volUp.value ?? 0) }),
            ActionTestCase(
                type: .volumeDown,
                setUp: { volDown.value = readVolume() },
                observe: { readVolume() <= (volDown.value ?? 100) },
                tearDown: { setVolume(volDown.value ?? 0) }),
            ActionTestCase(type: .playPause),
            ActionTestCase(type: .nextTrack),
            ActionTestCase(type: .previousTrack),
        ]

        // MARK: Capture
        let shot = Box<Set<String>>()
        cases += [
            ActionTestCase(type: .screenshotArea, interactiveNoFire: true),
            ActionTestCase(
                type: .screenshotFull,
                precondition: { CGPreflightScreenCaptureAccess() },
                setUp: { shot.value = desktopEntries() },
                observe: { !newDesktopPNGs(since: shot.value ?? []).isEmpty },
                tearDown: {
                    for path in newDesktopPNGs(since: shot.value ?? []) {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                }),
        ]

        // MARK: System
        let dark = Box<Bool>()
        let dock = Box<Bool>()
        cases += [
            ActionTestCase(
                type: .toggleDarkMode,
                setUp: { dark.value = readDarkMode() },
                observe: { readDarkMode() != (dark.value ?? false) },
                tearDown: { setDarkMode(dark.value ?? false) }),
            ActionTestCase(
                type: .toggleDockAutohide,
                setUp: { dock.value = readDockAutohide() },
                observe: { readDockAutohide() != (dock.value ?? false) },
                tearDown: { setDockAutohide(dock.value ?? false) }),
            ActionTestCase(type: .emptyTrash, destructive: true),
        ]

        // MARK: Open & Run
        let shellFile = tmpPath("shell.txt")
        let scriptFile = tmpPath("applescript.txt")
        let calc = Box<Bool>()
        cases += [
            ActionTestCase(
                type: .launchApp, parameter: "/System/Applications/Calculator.app",
                setUp: { calc.value = isRunning("com.apple.calculator") },
                observe: { isRunning("com.apple.calculator") },
                tearDown: { if calc.value == false { quitApp("com.apple.calculator") } }),
            ActionTestCase(type: .openURL, parameter: "file://" + NSTemporaryDirectory()),
            ActionTestCase(type: .openFileFolder, parameter: NSTemporaryDirectory()),
            ActionTestCase(
                type: .runShell, parameter: "touch '\(shellFile)'",
                setUp: { try? FileManager.default.removeItem(atPath: shellFile) },
                observe: { FileManager.default.fileExists(atPath: shellFile) },
                tearDown: { try? FileManager.default.removeItem(atPath: shellFile) }),
            ActionTestCase(
                type: .runAppleScript, parameter: "do shell script \"touch '\(scriptFile)'\"",
                setUp: { try? FileManager.default.removeItem(atPath: scriptFile) },
                observe: { FileManager.default.fileExists(atPath: scriptFile) },
                tearDown: { try? FileManager.default.removeItem(atPath: scriptFile) }),
            ActionTestCase(
                type: .runShortcut,
                parameter: ProcessInfo.processInfo.environment["MORECORNERS_E2E_SHORTCUT"] ?? "",
                precondition: { ProcessInfo.processInfo.environment["MORECORNERS_E2E_SHORTCUT"] != nil }),
            ActionTestCase(type: .pressKeys, parameter: "f15"),
        ]

        return cases
    }

    // MARK: - Observation helpers

    private static func sh(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func osa(_ script: String) -> String {
        sh("/usr/bin/osascript", ["-e", script])
    }

    static func readDarkMode() -> Bool {
        osa("tell application \"System Events\" to tell appearance preferences to get dark mode") == "true"
    }
    static func setDarkMode(_ on: Bool) {
        _ = osa("tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)")
    }
    static func readMuted() -> Bool { osa("output muted of (get volume settings)") == "true" }
    static func setMuted(_ on: Bool) { _ = osa("set volume \(on ? "with" : "without") output muted") }
    static func readVolume() -> Int { Int(osa("output volume of (get volume settings)")) ?? -1 }
    static func setVolume(_ value: Int) { _ = osa("set volume output volume \(value)") }

    static func readDockAutohide() -> Bool {
        sh("/usr/bin/defaults", ["read", "com.apple.dock", "autohide"]) == "1"
    }
    static func setDockAutohide(_ on: Bool) {
        _ = sh("/usr/bin/defaults",
               ["write", "com.apple.dock", "autohide", "-bool", on ? "true" : "false"])
        _ = sh("/usr/bin/killall", ["Dock"])
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
    static func quitApp(_ bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .forEach { $0.terminate() }
    }

    static func tmpPath(_ name: String) -> String {
        NSTemporaryDirectory() + "morecorners-e2e-\(name)"
    }

    private static var desktopDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
    }
    static func desktopEntries() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: desktopDir)) ?? [])
    }
    static func newDesktopPNGs(since before: Set<String>) -> [String] {
        desktopEntries().subtracting(before)
            .filter { $0.lowercased().hasSuffix(".png") }
            .map { (desktopDir as NSString).appendingPathComponent($0) }
    }
}
