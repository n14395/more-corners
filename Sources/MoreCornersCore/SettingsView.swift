import AppKit
import ApplicationServices
import SwiftUI

/// Width of the leading column that holds the "Default" label / modifier chips,
/// so the action pickers in all rows line up.
private let modifierColumnWidth: CGFloat = 108

/// Fixed content width for every tab, so the window keeps a constant width and
/// only its height changes as tabs are switched.
private let tabWidth: CGFloat = 800

/// Holds the system's hot corner assignments for the settings UI.
/// (A plain class rather than @State: the CLT toolchain here can't load
/// SwiftUI's macro plugin, so macro-based wrappers don't compile.)
final class SystemCornerModel: ObservableObject {
    static let shared = SystemCornerModel()
    @Published var assignments: [Corner: SystemHotCorners.Assignment] = [:]
    func refresh() { assignments = SystemHotCorners.assignments() }
}

/// Live Accessibility-permission state for the Settings UI. Many actions
/// (media, brightness, spaces, keystrokes) silently do nothing without it.
final class PermissionsModel: ObservableObject {
    static let shared = PermissionsModel()
    @Published var accessibilityTrusted = AXIsProcessTrusted()
    func refresh() { accessibilityTrusted = AXIsProcessTrusted() }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var systemCorners = SystemCornerModel.shared
    @ObservedObject private var permissions = PermissionsModel.shared

    private var systemAssignments: [Corner: SystemHotCorners.Assignment] {
        systemCorners.assignments
    }

    private var clashingCorners: [Corner] {
        Corner.allCases.filter { corner in
            guard let assignment = systemAssignments[corner] else { return false }
            return SystemHotCorners.clashes(assignment, with: settings.config(for: corner))
        }
    }

    var body: some View {
        // No fixed frame: each tab sizes to its content, and the hosting
        // controller (sizingOptions = .preferredContentSize) resizes the window
        // to match — so the window grows and shrinks as tabs are switched.
        TabView {
            cornersTab
                .tabItem { Label("Corners", systemImage: "square.grid.2x2") }
            behaviorTab
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
            exclusionsTab
                .tabItem { Label("Exclusions", systemImage: "nosign") }
        }
        .onAppear { systemCorners.refresh(); permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            systemCorners.refresh()
            permissions.refresh()
        }
    }

    // MARK: - Corners tab

    private var cornersTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !clashingCorners.isEmpty { clashBanner }
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    cornerCard(.topLeft)
                    cornerCard(.topRight)
                }
                GridRow {
                    cornerCard(.bottomLeft)
                    cornerCard(.bottomRight)
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                Text("A corner's Default runs unless the modifiers you're holding exactly match one of its “while holding” rows. Turn a corner's switch off to keep its actions but stop it firing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: tabWidth)
    }

    private func cornerCard(_ corner: Corner) -> CornerCard {
        CornerCard(corner: corner,
                   systemAssignment: systemAssignments[corner],
                   clash: clashingCorners.contains(corner))
    }

    private var clashBanner: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS hot corners are also active")
                        .font(.headline)
                    ForEach(clashingCorners, id: \.self) { corner in
                        if let assignment = systemAssignments[corner] {
                            let modifierNote = assignment.modifiers.isEmpty
                                ? "" : " (while holding \(assignment.modifiers.symbols))"
                            Text("\(corner.label) also triggers “\(SystemHotCorners.name(for: assignment.code))”\(modifierNote) — both actions will run.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button("Open System Settings…") {
                    SystemHotCorners.openSystemSettings()
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Behavior tab

    private var behaviorTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            GroupBox("Triggering") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Activate by pushing into the corner", isOn: $settings.slamToActivate)
                        .help("Fire the instant the pointer reaches the very corner, like macOS's own hot corners — instead of dwelling in a zone. Ignores the delay and size below.")
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Trigger delay").frame(width: 110, alignment: .leading)
                            Slider(value: $settings.dwell, in: 0...1)
                            Text(String(format: "%.2f s", settings.dwell))
                                .monospacedDigit().frame(width: 55, alignment: .trailing)
                        }
                        HStack {
                            Text("Corner size").frame(width: 110, alignment: .leading)
                            Slider(value: $settings.cornerSize, in: 2...24, step: 1,
                                   onEditingChanged: { editing in
                                       if editing { CornerZonePreview.show(size: settings.cornerSize) }
                                       else { CornerZonePreview.hide() }
                                   })
                                .onChange(of: settings.cornerSize) { newValue in
                                    CornerZonePreview.update(size: newValue)
                                }
                            Text("\(Int(settings.cornerSize)) px")
                                .monospacedDigit().frame(width: 55, alignment: .trailing)
                        }
                    }
                    .disabled(settings.slamToActivate)
                    .opacity(settings.slamToActivate ? 0.4 : 1)
                    .help(settings.slamToActivate
                          ? "Delay and size don't apply while “push into the corner” is on."
                          : "Drag Corner size to preview the trigger zones on screen.")

                    HStack(spacing: 20) {
                        Toggle("Hot corners enabled", isOn: $settings.enabled)
                        Toggle("All displays", isOn: $settings.allScreens)
                    }
                    Toggle("Pause in full-screen apps", isOn: $settings.suppressInFullScreen)
                        .help("When the frontmost window covers the whole screen (video, games, presentations), hot corners won't fire.")
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Feedback when a corner fires") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Confirms a corner triggered — useful for actions with no visible effect.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        Toggle("Corner flash", isOn: $settings.feedbackFlash)
                        Toggle("Haptic tap", isOn: $settings.feedbackHaptic)
                            .help("Force Touch trackpads only.")
                    }
                    HStack(spacing: 8) {
                        Toggle("Sound", isOn: $settings.feedbackSound)
                        Picker("", selection: $settings.feedbackSoundName) {
                            ForEach(AppSettings.availableSoundNames, id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden().frame(width: 150)
                        .disabled(!settings.feedbackSound)
                        Button {
                            NSSound(named: settings.feedbackSoundName)?.play()
                        } label: {
                            Image(systemName: "speaker.wave.2")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!settings.feedbackSound)
                        .help("Preview")
                        Spacer()
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("General") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 20) {
                        Toggle("Launch at login", isOn: $settings.launchAtLogin)
                            .onChange(of: settings.launchAtLogin) { value in
                                settings.applyLaunchAtLogin(value)
                            }
                        Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                            .help("When off, reopen this window by launching MoreCorners again from Finder, Spotlight, or Launchpad.")
                    }
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: permissions.accessibilityTrusted
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(permissions.accessibilityTrusted ? .green : .orange)
                        Text(permissions.accessibilityTrusted
                             ? "Accessibility access granted"
                             : "Accessibility access needed for media, space & keystroke actions")
                            .font(.callout)
                        Spacer()
                        if !permissions.accessibilityTrusted {
                            Button("Open Settings…") { openAccessibilitySettings() }
                        }
                        Button { permissions.refresh() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Re-check permission")
                    }
                    Divider()
                    HStack {
                        Button("Export Settings…") { exportSettings() }
                        Button("Import Settings…") { importSettings() }
                        Button("Reset to Defaults…") { confirmReset() }
                        Spacer()
                    }
                    Text("AppleScript actions (Dark Mode, Trash, Log Out) prompt for Automation access on first use.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: tabWidth)
    }

    private func exportSettings() {
        guard let data = settings.exportData() else { NSSound.beep(); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MoreCorners.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        if !settings.importData(data) {
            let alert = NSAlert()
            alert.messageText = "Couldn't import settings"
            alert.informativeText = "That file isn't a valid MoreCorners settings export."
            alert.runModal()
        }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = "Reset all settings to defaults?"
        alert.informativeText = "This replaces your corners and preferences with the built-in default layout. This can't be undone."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            settings.resetToDefaults()
            systemCorners.refresh()
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Exclusions tab

    private var exclusionsTab: some View { ExclusionsView() }
}

// MARK: - Corner card

struct CornerCard: View {
    let corner: Corner
    var systemAssignment: SystemHotCorners.Assignment?
    var clash = false
    @ObservedObject private var settings = AppSettings.shared

    private var config: Binding<CornerConfig> {
        Binding(
            get: { settings.corners[corner] ?? CornerConfig() },
            set: { settings.corners[corner] = $0 }
        )
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                header
                configRows
                    .opacity(config.wrappedValue.enabled ? 1 : 0.5)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: corner.symbol)
            Text(corner.label).font(.headline)
            Toggle("", isOn: config.enabled)
                .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                .help(config.wrappedValue.enabled ? "Corner is on — turn off to stop it firing"
                                                  : "Corner is off — its actions won't fire")
            Spacer()
            if let assignment = systemAssignment {
                if clash {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
                let modifierNote = assignment.modifiers.isEmpty
                    ? "" : " (\(assignment.modifiers.symbols))"
                Text("macOS: \(SystemHotCorners.name(for: assignment.code))\(modifierNote)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(clash
                        ? "macOS also triggers “\(SystemHotCorners.name(for: assignment.code))” in this corner — both actions will run. Use “Hot Corners…” in System Settings → Desktop & Dock to change it."
                        : "macOS has “\(SystemHotCorners.name(for: assignment.code))” assigned to this corner in System Settings. If you add an action here, both will run.")
            }
        }
    }

    private var configRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Default action row
            HStack(spacing: 6) {
                Text("Default")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: modifierColumnWidth, alignment: .leading)
                ActionMenu(spec: config.base)
                TestButton(spec: config.base.wrappedValue)
            }
            ParameterRow(spec: config.base)

            // Modifier overrides
            if !config.wrappedValue.variants.isEmpty {
                Divider()
                Text("While holding…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(config.variants) { $variant in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ModifierChips(modifiers: $variant.modifiers)
                            .frame(width: modifierColumnWidth, alignment: .leading)
                        ActionMenu(spec: $variant.spec)
                        TestButton(spec: variant.spec)
                        Button {
                            config.variants.wrappedValue.removeAll { $0.id == variant.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this modifier action")
                    }
                    if variant.modifiers.isEmpty {
                        Text("Select at least one modifier key")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.leading, modifierColumnWidth + 6)
                    }
                    ParameterRow(spec: $variant.spec)
                }
            }

            Button {
                config.variants.wrappedValue.append(
                    CornerConfig.Variant(modifiers: nextUnusedModifiers()))
            } label: {
                Label("Add modifier action", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }

    private func nextUnusedModifiers() -> ModifierKeys {
        let used = Set(config.wrappedValue.variants.map(\.modifiers))
        let candidates: [ModifierKeys] = [
            .command, .option, .control, .shift,
            [.command, .shift], [.command, .option], [.command, .control],
            [.option, .shift], [.control, .option], [.control, .shift],
        ]
        return candidates.first { !used.contains($0) } ?? []
    }
}

// MARK: - Exclusions

private struct ExclusionsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hot corners won't fire while one of these apps is frontmost — handy for games or full-screen creative apps.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                if settings.excludedApps.isEmpty {
                    Text("No excluded apps.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(settings.excludedApps) { app in
                            HStack(spacing: 8) {
                                Image(nsImage: icon(for: app.bundleID))
                                    .resizable().frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                    Text(app.bundleID)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button { remove(app) } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless).help("Remove")
                            }
                            .padding(.vertical, 5)
                            if app.id != settings.excludedApps.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            HStack {
                Menu("Add Running App") {
                    let apps = runningApps()
                    if apps.isEmpty {
                        Text("No other apps running")
                    } else {
                        ForEach(apps, id: \.bundleID) { app in
                            Button(app.name) { add(bundleID: app.bundleID, name: app.name) }
                        }
                    }
                }
                .frame(width: 170)
                Button("Choose from Applications…") { addViaPanel() }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: tabWidth, alignment: .topLeading)
    }

    private func add(bundleID: String, name: String) {
        guard !settings.excludedApps.contains(where: { $0.bundleID == bundleID }) else { return }
        settings.excludedApps.append(ExcludedApp(bundleID: bundleID, name: name))
    }

    private func remove(_ app: ExcludedApp) {
        settings.excludedApps.removeAll { $0.bundleID == app.bundleID }
    }

    private func runningApps() -> [(bundleID: String, name: String)] {
        let selfBID = Bundle.main.bundleIdentifier
        let already = Set(settings.excludedApps.map(\.bundleID))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (bundleID: String, name: String)? in
                guard let bid = app.bundleIdentifier, bid != selfBID, !already.contains(bid)
                else { return nil }
                return (bundleID: bid, name: app.localizedName ?? bid)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func addViaPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier else { return }
        add(bundleID: bid, name: url.deletingPathExtension().lastPathComponent)
    }

    private func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}

// MARK: - Row pieces

/// Four toggle chips (⌃ ⌥ ⇧ ⌘) composing an exact modifier combination.
private struct ModifierChips: View {
    @Binding var modifiers: ModifierKeys

    var body: some View {
        HStack(spacing: 2) {
            chip("⌃", .control, "Control")
            chip("⌥", .option, "Option")
            chip("⇧", .shift, "Shift")
            chip("⌘", .command, "Command")
        }
    }

    private func chip(_ symbol: String, _ key: ModifierKeys, _ name: String) -> some View {
        Toggle(symbol, isOn: Binding(
            get: { modifiers.contains(key) },
            set: { on in
                if on { modifiers.insert(key) } else { modifiers.remove(key) }
            }))
            .toggleStyle(.button)
            .controlSize(.small)
            .help("Require \(name) (\(symbol)) to be held")
    }
}

private struct ActionMenu: View {
    @Binding var spec: ActionSpec

    var body: some View {
        Picker("Action", selection: $spec.action) {
            Text("None").tag(ActionType.none)
            ForEach(ActionGroup.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(group.actions, id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }
            }
        }
        .labelsHidden()
    }
}

private struct TestButton: View {
    let spec: ActionSpec

    var body: some View {
        Button {
            ActionRunner.run(spec)
        } label: {
            Image(systemName: "play.circle")
        }
        .buttonStyle(.borderless)
        .disabled(spec.action == .none)
        .help("Test this action now")
    }
}

private struct ParameterRow: View {
    @Binding var spec: ActionSpec

    var body: some View {
        if spec.action.needsParameter {
            HStack(spacing: 6) {
                TextField(spec.action.parameterPlaceholder, text: $spec.parameter)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                if spec.action.usesFilePicker {
                    Button("Choose…") { choose() }
                        .controlSize(.small)
                }
            }
            .padding(.leading, modifierColumnWidth + 6)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        let forApp = spec.action == .launchApp
        panel.canChooseFiles = true
        panel.canChooseDirectories = !forApp
        panel.allowsMultipleSelection = false
        if forApp {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.applicationBundle]
        }
        if panel.runModal() == .OK, let url = panel.url {
            spec.parameter = url.path
        }
    }
}
