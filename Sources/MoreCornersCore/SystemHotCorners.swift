// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import AppKit

/// Reads the hot corner assignments macOS itself has configured
/// (System Settings → Desktop & Dock → Hot Corners…), so we can warn
/// about corners where both apps would fire.
enum SystemHotCorners {
    struct Assignment {
        let code: Int
        let modifiers: ModifierKeys
    }

    static func assignments() -> [Corner: Assignment] {
        guard let dock = UserDefaults(suiteName: "com.apple.dock") else { return [:] }
        let keys: [(Corner, String)] = [
            (.topLeft, "tl"), (.topRight, "tr"), (.bottomLeft, "bl"), (.bottomRight, "br"),
        ]
        var result: [Corner: Assignment] = [:]
        for (corner, key) in keys {
            let code = dock.integer(forKey: "wvous-\(key)-corner")
            // 0 = never configured, 1 = "no action"
            guard code > 1 else { continue }
            let raw = dock.integer(forKey: "wvous-\(key)-modifier")
            let modifiers = ModifierKeys(flags: NSEvent.ModifierFlags(rawValue: UInt(raw)))
            result[corner] = Assignment(code: code, modifiers: modifiers)
        }
        return result
    }

    static func name(for code: Int) -> String {
        switch code {
        case 2: return "Mission Control"
        case 3: return "Application Windows"
        case 4: return "Desktop"
        case 5: return "Start Screen Saver"
        case 6: return "Disable Screen Saver"
        case 7: return "Dashboard"
        case 10: return "Put Display to Sleep"
        case 11: return "Launchpad"
        case 12: return "Notification Center"
        case 13: return "Lock Screen"
        case 14: return "Quick Note"
        default: return "an action"
        }
    }

    /// True when the system corner and our config would both fire for some
    /// modifier state. A system corner without a modifier requirement fires
    /// no matter what is held, so it clashes with any configured corner; one
    /// bound to a modifier combo clashes only if our corner responds to it.
    static func clashes(_ assignment: Assignment, with config: CornerConfig) -> Bool {
        if assignment.modifiers.isEmpty { return config.isConfigured }
        return config.resolve(held: assignment.modifiers) != nil
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
