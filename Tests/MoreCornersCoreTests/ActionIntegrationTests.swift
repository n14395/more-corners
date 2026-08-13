import XCTest
import AppKit
@testable import MoreCornersCore

/// End-to-end harness that actually *fires* every assignable action, once per
/// connected display, in both the focused-display and unfocused-display state
/// — directly exercising the multi-monitor behavior the app cares about.
///
/// This is opt-in and skipped by default, because it drives real system UI on
/// the machine running it. Enable with environment variables:
///
///   MORECORNERS_E2E=1              run the harness at all
///   MORECORNERS_E2E_DESTRUCTIVE=1  also fire lock/sleep/logout/quit/trash/hide
///   MORECORNERS_E2E_ONLY=a,b,c     restrict to these action raw values
///
/// For each action it either asserts an observable effect (dark-mode flipped,
/// a file was created, an app launched, …) or, when the effect can't be
/// checked from a public API (Mission Control, Control Center, a keystroke),
/// records it on a printed manual-verification checklist. Destructive and
/// interactive actions are never fired unless explicitly opted in.
final class ActionIntegrationTests: XCTestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var e2eEnabled: Bool { env["MORECORNERS_E2E"] == "1" }
    private var destructiveEnabled: Bool { env["MORECORNERS_E2E_DESTRUCTIVE"] == "1" }
    private var onlyFilter: Set<String>? {
        guard let raw = env["MORECORNERS_E2E_ONLY"], !raw.isEmpty else { return nil }
        return Set(raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        })
    }

    func testEveryActionOnFocusedAndUnfocusedDisplays() throws {
        try XCTSkipUnless(e2eEnabled, """
            End-to-end action harness is opt-in. Re-run with MORECORNERS_E2E=1 \
            (and grant the test runner Accessibility + Screen Recording). Add \
            MORECORNERS_E2E_DESTRUCTIVE=1 to include lock/sleep/logout/quit, or \
            MORECORNERS_E2E_ONLY=runShell,toggleKeepAwake to target a subset.
            """)

        // A window-server connection is needed for the focus-control windows;
        // give the test process an (accessory) app identity so AppKit is happy.
        NSApplication.shared.setActivationPolicy(.accessory)
        let trusted = AXIsProcessTrusted()
        let displays = NSScreen.screens
        XCTAssertFalse(displays.isEmpty, "no displays?")

        // Every assignable action is covered exactly once below.
        let cases = Self.makeCases()
        XCTAssertEqual(Set(cases.map(\.type)),
                       Set(ActionType.allCases.filter { $0 != .none }),
                       "every assignable action must have an E2E case")

        var passes: [String] = []
        var failures: [String] = []
        var checklist: [String] = []

        for (index, screen) in displays.enumerated() {
            // "focused" = the corner's own display has key focus; "unfocused"
            // = a different display is focused. The second only exists with 2+.
            let focusStates: [Bool] = displays.count > 1 ? [true, false] : [true]
            for focused in focusStates {
                let where_ = "display \(index) [\(focused ? "focused" : "unfocused")]"

                if displays.count > 1 {
                    guard trusted else {
                        checklist.append("\(where_): skipped — grant Accessibility to move focus between displays")
                        continue
                    }
                    let focusTarget = focused ? screen : otherDisplay(than: screen, in: displays)
                    focusDisplay(focusTarget)
                }

                for testCase in cases {
                    if let only = onlyFilter, !only.contains(testCase.type.rawValue) { continue }
                    let tag = "\(where_) \(testCase.type.rawValue)"

                    if testCase.destructive && !destructiveEnabled {
                        checklist.append("\(tag): skipped destructive (set MORECORNERS_E2E_DESTRUCTIVE=1)")
                        continue
                    }
                    if testCase.type.needsAccessibility && !trusted {
                        checklist.append("\(tag): skipped — test runner lacks Accessibility")
                        continue
                    }
                    if let precheck = testCase.precondition, !precheck() {
                        checklist.append("\(tag): skipped — precondition not met (e.g. Screen Recording)")
                        continue
                    }

                    // Put the pointer on this display: ActionRunner picks the
                    // target display from the live pointer location.
                    warpPointerToCenter(of: screen)

                    if testCase.interactiveNoFire {
                        checklist.append("\(tag): not fired (interactive UI); verify manually on display \(index)")
                        continue
                    }

                    testCase.setUp?()
                    fireAndSettle(ActionSpec(action: testCase.type, parameter: testCase.parameter))

                    if let observe = testCase.observe {
                        if observe() {
                            passes.append(tag)
                        } else {
                            failures.append(tag)
                        }
                    } else {
                        checklist.append("\(tag): fired; verify manually it acted on display \(index)")
                    }
                    testCase.tearDown?()
                    dismissTransientUI()
                }
            }
        }

        printReport(passes: passes, failures: failures, checklist: checklist,
                    displayCount: displays.count, trusted: trusted)
        XCTAssertTrue(failures.isEmpty,
                      "\(failures.count) observable action(s) failed — see report above")
    }

    // MARK: - Report

    private func printReport(passes: [String], failures: [String],
                             checklist: [String], displayCount: Int, trusted: Bool) {
        print("""

        ================ MoreCorners E2E action report ================
        displays: \(displayCount)   test-runner Accessibility: \(trusted ? "granted" : "MISSING")
        auto-observed: \(passes.count) passed, \(failures.count) failed
        ---------------------------------------------------------------
        """)
        for line in passes { print("  ✅ \(line)") }
        for line in failures { print("  ❌ \(line)") }
        print("  --- manual verification checklist ---")
        for line in checklist { print("  [ ] \(line)") }
        print("===============================================================\n")
    }

    // MARK: - Focus & pointer control

    /// A borderless window that can take key focus, used to pull the "active
    /// display" onto a chosen screen (the same trick the app uses).
    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private func otherDisplay(than screen: NSScreen, in all: [NSScreen]) -> NSScreen {
        all.first { $0 != screen } ?? screen
    }

    private func focusDisplay(_ screen: NSScreen) {
        let frame = NSRect(x: screen.frame.midX - 5, y: screen.frame.midY - 5,
                           width: 10, height: 10)
        let window = KeyableWindow(contentRect: frame, styleMask: .borderless,
                                   backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false   // ARC owns it; avoid a double free
        window.level = .floating
        window.alphaValue = 0.01
        window.backgroundColor = .clear
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // A synthetic click on our own window makes the display switch "real"
        // (programmatic activation alone doesn't move the active display).
        let primaryTop = NSScreen.screens[0].frame.maxY
        let click = CGPoint(x: window.frame.midX, y: primaryTop - window.frame.midY)
        postClick(at: click)
        settle(0.3)
        window.close()
    }

    private func warpPointerToCenter(of screen: NSScreen) {
        let primaryTop = NSScreen.screens[0].frame.maxY
        let center = CGPoint(x: screen.frame.midX, y: primaryTop - screen.frame.midY)
        CGWarpMouseCursorPosition(center)
    }

    private func postClick(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Press Escape to close any panel/menu an action may have opened, so the
    /// next case starts from a clean state.
    private func dismissTransientUI() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        settle(0.2)
    }

    // MARK: - Firing & waiting

    /// Fire an action and spin the run loop long enough for its async work
    /// (AppleScript, shells, the focus-grab dance) to complete.
    private func fireAndSettle(_ spec: ActionSpec) {
        ActionRunner.run(spec)
        settle(1.3)
    }

    private func settle(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }
}
