# MoreCorners

A menu-bar-only macOS hot corners app with a much larger action catalog than
System Settings offers — ~30 actions, per-corner modifier requirements, a
configurable trigger delay, and parameterized custom actions.

A fresh install starts from a ready-to-use default layout (top corners for the
menu bar / spaces, Quick Note and Show Desktop below) rather than an empty grid;
**Reset to Defaults** restores it.

## Build & run

Three equivalent ways:

```sh
./build.sh run    # build MoreCorners.app and (re)launch it (no .dmg)
./build.sh        # build the bundle AND package MoreCorners-<version>.dmg
./build.sh app    # build the bundle only, no .dmg (faster dev loop)
make run          # same via make (also: make build / app / dmg / clean)
open MoreCorners.xcodeproj   # edit/build/run in Xcode (⌘R)
```

The shell builds need only the Xcode Command Line Tools. The Xcode project
shares the same sources and `Info.plist`. Both sign with your Apple
Development certificate when available (see Permissions below), so TCC grants
persist across rebuilds. Note that `xcodebuild` from the terminal requires
full Xcode (`sudo xcode-select -s /Applications/Xcode-beta.app` or prefix
with `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`).

On first launch the settings window opens automatically. After that, use the
menu bar icon (top-left-corner rectangle) → **Settings…**. If you hide the menu
bar icon (see Behavior options), reopen Settings by **launching MoreCorners
again** from Finder, Spotlight, or Launchpad — the running app routes the
re-launch to a Settings window instead of starting a second copy.

## Distributing

A plain `./build.sh` (or `make dmg`) also packages **`MoreCorners-<version>.dmg`**
— a compressed, drag-to-install image containing the app and an `/Applications`
alias — ready to attach to a GitHub release. It's a build artifact, so it's
gitignored rather than committed.

**Gatekeeper caveat:** the app is signed with an **Apple Development** (or
ad-hoc) certificate, *not* a Developer ID with notarization. On another Mac,
Gatekeeper will therefore refuse to open it on a double-click. Until the app is
notarized, tell users to either:

- **right-click the app → Open**, then confirm once, or
- run `xattr -dr com.apple.quarantine /Applications/MoreCorners.app` after
  copying it in.

Removing the warning entirely requires a paid Apple Developer account: sign with
a **Developer ID Application** certificate and notarize the `.dmg`
(`xcrun notarytool submit … --wait` then `xcrun stapler staple`). Set
`CODESIGN_IDENTITY="Developer ID Application: …"` before `./build.sh` to sign
with it; the notarize/staple steps are not yet scripted.

## Project layout

The logic lives in a `MoreCornersCore` library so it can be unit tested; the
`MoreCorners` executable is a three-line `main.swift` that calls into it. The
hand-written Xcode project compiles every source into one app target instead
(no library), which is why `main.swift` guards its import with
`#if canImport(MoreCornersCore)`.

```
Sources/MoreCorners/main.swift        # executable entry point
Sources/MoreCornersCore/*.swift       # all app logic (library)
Tests/MoreCornersCoreTests/*.swift    # XCTest suite
```

## Tests

```sh
# Unit tests — deterministic, fast, no side effects. Needs the full Xcode
# toolchain because XCTest ships with Xcode, not the Command Line Tools.
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
```

Two layers:

**Unit tests** (always run) cover the pure logic: per-corner action resolution
and modifier matching, the action catalog's invariants, corner geometry and
the exposed-edge check, the dwell/rearm state machine (`CornerTrigger`),
v1→v2 settings migration, system hot-corner clash detection, and the key-spec
and symbolic-hotkey parsers.

**End-to-end action harness** (`ActionIntegrationTests`, opt-in) actually
*fires every assignable action, once per connected display, in both the
focused-display and unfocused-display state* — the multi-monitor behavior the
app exists for. It asserts the effects that are observable from public APIs
(dark mode flipped, Dock auto-hide flipped, mute/volume changed, a file
created by a shell/AppleScript action, an app launched, a screenshot written,
the keep-awake assertion toggled) and prints a manual-verification checklist
for the ones that aren't (Mission Control, Control Center, Notification
Center, the Apple menu, brightness, media keys, synthesized keystrokes).

It is skipped unless opted in, because it drives real system UI:

```sh
# All non-destructive actions on every display:
MORECORNERS_E2E=1 DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --filter ActionIntegrationTests

# A safe subset (no visible system changes):
MORECORNERS_E2E=1 MORECORNERS_E2E_ONLY=runShell,toggleKeepAwake … swift test …

# Include lock / sleep / logout / quit / empty-trash / hide:
MORECORNERS_E2E=1 MORECORNERS_E2E_DESTRUCTIVE=1 … swift test …
```

Requirements & caveats for the harness:

- The **test runner** (`xctest`) needs its own **Accessibility** grant to
  synthesize input and to move focus between displays, and **Screen
  Recording** for the screenshot check. Ungranted actions are skipped with a
  note rather than failing.
- The unfocused-display cases only run with **two or more displays** (and
  "Displays have separate Spaces" on); on a single display they're skipped.
- Destructive and interactive (screenshot-selection) actions are never fired
  unless explicitly opted in.
- Set `MORECORNERS_E2E_SHORTCUT=<name>` to exercise the "Run Shortcut" action.

## Actions

| Group | Actions |
|---|---|
| Windows & Desktop | Mission Control, Application Windows, Show Desktop, Launchpad/Apps, Open Control Center, Open Notification Center, Open Apple Menu, Open Quick Note, Next Space, Previous Space, Move App to Next/Previous Space, Hide Frontmost App, Hide All Other Apps, Quit Frontmost App |
| Display & Power | Lock Screen, Start Screen Saver, Display Sleep, System Sleep, Toggle Keep Awake, Brightness Up/Down, Log Out |
| Sound & Media | Toggle Mute, Volume Up/Down, Play/Pause, Next/Previous Track |
| Capture | Screenshot Area → Clipboard, Screenshot Screen → Desktop |
| System | Toggle Dark Mode, Toggle Dock Auto-Hide, Empty Trash |
| Open & Run | Launch App, Open URL, Open File/Folder, Run Shell Command, Run AppleScript, Run Shortcuts Shortcut, Press Keyboard Shortcut |

Parameterized actions show a text field (and a file picker where relevant).
`Open URL` accepts a bare host like `example.com` (it defaults to `https://`).
`Press Keyboard Shortcut` takes specs like `cmd+shift+4`, `ctrl+left`, `f11`.
`Run Shortcuts Shortcut` runs any shortcut from the Shortcuts app by name —
handy for things with no public API (Do Not Disturb, Focus modes, HomeKit…).

## Per-corner options

Each corner has a **Default** action plus any number of **modifier overrides**
("While holding…" rows). An override binds an exact modifier combination —
picked with ⌃ ⌥ ⇧ ⌘ toggle chips, combos like ⌘⇧ included — to its own action:

- Hit the corner → the Default runs.
- Hit the corner while holding ⌘ (and a ⌘ row exists) → that action runs instead.
- Held modifiers must match a row *exactly* (⌘⇧ doesn't trigger the ⌘ row);
  with no exact match, the Default runs.
- Want a corner that only fires with a modifier? Leave Default as "None" and
  add overrides — the corner then waits until the right modifiers are held.
- If several rows have the same combo, the first one wins.

Every row has its own ▶ test button and parameter field.

The settings window is organized into three tabs: **Corners** (per-corner
actions and clash warnings), **Behavior** (the options below, feedback, and
import/export), and **Exclusions** (the per-app list).

## Behavior options

- **Trigger delay** (0–1 s dwell before firing; prevents accidental triggers).
- **Corner size** (2–24 px hot zone). Dragging the slider flashes the actual
  trigger zones on every active display, so you can see what a size covers.
- **Activate by pushing into the corner** — an alternative to the dwell: fire
  the instant the pointer reaches the very corner (like macOS's own hot
  corners), with no delay. Trigger delay and corner size don't apply in this
  mode.
- **All displays** — corners are detected on every display, but only *exposed*
  corners of the combined desktop count, so the pointer can cross between
  monitors without firing.
- **Per-corner switch** — each corner card has an on/off toggle that keeps its
  configuration but stops it firing (the ▶ test buttons still work). A corner
  turned off dims its rows.
- **Pause in full-screen apps** — when the frontmost window covers its whole
  display (video, games, presentations), no corner fires. Detected from the
  window list, so it needs no permissions (a merely maximized window, which
  leaves the menu-bar strip, still fires).
- **Exclusions** — apps that suppress hot corners while frontmost (games,
  creative apps). Add running apps from a menu or browse the Applications
  folder; matched by bundle ID.
- **Trigger feedback** — optional confirmation when a corner fires, useful for
  actions with no visible effect: a **corner flash** (a soft glow at the corner
  that fired), a **system sound** (choose which), and/or a **haptic tap** (Force
  Touch trackpads). Any combination.
- **Export / Import / Reset Settings** — save all settings to a JSON file and
  load them back (backup or move between Macs), or reset everything to the
  built-in default layout. Older exports still load — fields added later fall
  back to their defaults.
- **Accessibility status** — the Behavior tab shows, live, whether the app has
  the Accessibility grant that media / space / keystroke actions need, with a
  one-click jump to System Settings when it doesn't (those actions otherwise
  fail silently).
- **Launch at login** (requires running from the `.app` bundle).
- **Show menu bar icon** — hide it for a fully invisible utility; the app keeps
  running and corners still fire. With the icon hidden, re-launching the app
  (Finder / Spotlight / Launchpad / `open -a MoreCorners`) reopens Settings, so
  there's always a way back. The first time you hide it, a one-time alert
  explains this. When shown, the icon dims with a slash while paused and carries
  a dot while Keep Awake is on.
- **Pause** — the menu bar item pauses hot corners indefinitely or for a set
  time (15 min / 1 hour / 2 hours / until tomorrow morning); a timed pause shows
  its resume time and auto-resumes. Turning corners back on cancels it.
- Actions never fire while a mouse button is down (drags/selections are safe).
- After firing, the pointer must leave the corner area before it can re-arm.
- Multi-display: menu bar actions (Apple Menu, Control Center, Notification
  Center) open on the display whose corner you hit, not the focused one —
  when the item lives on another display's menu bar, the app clicks the
  equivalent spot in the corner display's menu bar and restores the pointer.
  Notification Center and Quick Note (globe-shortcut based: fn+N / fn+Q) get
  the corner's display via a brief synthetic click on an invisible 10×10 pt
  helper window there before the shortcut fires — programmatic activation
  alone doesn't move the "active display"; a (synthetic) user click does.
  (All of this requires "Displays have separate Spaces".)

## System hot corner clash detection

The settings window reads macOS's own hot corner assignments (the
`wvous-*-corner` keys in `com.apple.dock`). Every corner card shows what
macOS has assigned there (e.g. "macOS: Launchpad") whenever the system uses
that corner, and a warning banner plus a ⚠️ badge appear on any corner where
**both** MoreCorners and macOS would actually fire — with modifier awareness:
a system corner with no modifier requirement fires no matter what is held, so
it clashes with any configured corner, while one bound to "⌘ only" clashes
only if your corner responds to ⌘. The banner's button jumps to System
Settings → Desktop & Dock, where the system corners can be set to "–". The
check re-runs whenever the settings window regains focus.

## Permissions

Corner detection itself needs **no permissions** (it polls the global mouse
position; no event tap, no input monitoring).

Some actions need one-time grants:

| Permission | Needed by |
|---|---|
| Accessibility | Play/Pause, Next/Previous Track, Brightness, Press Keyboard Shortcut, Open Control Center, Open Notification Center, Open Apple Menu, Open Quick Note, Next/Previous Space, Move App to Next/Previous Space |

Quick Note (fn+Q) and Notification Center (fn+N) work by synthesizing the
built-in globe shortcuts, so those must remain enabled in System Settings →
Keyboard. (Mission Control, Application Windows, and Show Desktop no longer
depend on a shortcut — see the notes below.)
| Automation (System Events / Finder) | Toggle Dark Mode, Empty Trash, Log Out |
| Screen Recording | Screenshot actions (macOS prompts via `screencapture`) |

`build.sh` signs with your Apple Development certificate when one is in the
keychain (override with `CODESIGN_IDENTITY=<hash-or-name>`), and the Xcode
project uses team-based automatic signing. Developer-cert TCC grants are keyed
to team + bundle ID, so **permissions survive rebuilds** — and script builds
and Xcode builds share the same grants. Only if no certificate is found does
the script fall back to ad-hoc signing, where every rebuild resets permissions
(the build output warns when this happens).

## Notes

- Mission Control, Application Windows, and Show Desktop are driven via
  `CoreDockSendNotification` (the private Dock notification API exported by
  HIToolbox) — the mechanism the Dock itself uses. This survives macOS
  releases where the old Mission Control binary moved and synthesized
  ⌃-arrow shortcuts stopped working. It needs no Accessibility permission.
- Launchpad was removed in macOS 26 and replaced by the "Apps" launcher
  (`/System/Applications/Apps.app`). The "Launchpad / Apps" action toggles
  Launchpad where it still exists, opens the Apps drawer on macOS 26+, and
  falls back to the Applications folder if neither is present.
- Open Control Center works even though the Control Center process exposes an
  empty accessibility tree on recent macOS: the app hit-tests the menu bar of
  the pointer's display via the system-wide accessibility element to locate
  the Control Center menu extra, then presses it (so it opens on the right
  display). This needs Accessibility.
- Next/Previous Space switch spaces by posting synthetic **trackpad
  dock-swipe gestures** (not keyboard shortcuts), so they work regardless of
  your Mission Control keyboard settings. On macOS 27 these gesture events
  must carry a serialized IOHID payload in CGEvent field 4205 — the technique
  is ported from the SpacesMenu app. The swipe acts on the display under the
  pointer, which for a hot-corner trigger is the corner's own display.
- Move App to Next/Previous Space reproduces the manual technique (the private
  `CGSMoveWindowsToManagedSpace` call no-ops for unentitled apps on macOS 26+):
  it grabs the focused window's title bar with a synthetic mouse-down and, while
  holding it, triggers the native "Move a space" shortcut — the window rides
  across to the adjacent space and you follow it. Details that make it reliable:
  the grab point is the gap between the close and minimize buttons (draggable on
  every window, unlike a toolbar); the synthetic mouse events clear their flags,
  so triggering the action with a modifier held (e.g. a ⌃+corner) doesn't turn
  the grab into a control-click; and the shortcut is read live from your actual
  `Move left/right a space` binding, so a remapped chord still works. It verifies
  the window arrived and **beeps** if not. Needs Accessibility.
- **Coexisting with another space manager** (e.g. SpacesMenu): apps that put an
  event tap on the space-switch chord will swallow the shortcut mid-drag and the
  move stalls. Before each move, MoreCorners posts a
  `dev.nwf.MoreCorners.windowMoveBegan`/`Ended` distributed notification; a peer
  can observe it and stand its tap down for the duration (a self-clearing 3 s
  safety flag covers a crash). Neither app depends on the other — the signal is
  simply ignored if no one is listening.
- Lock Screen uses `SACLockScreenImmediate` from the private login framework
  (the same approach common utilities use).
- Settings persist in `defaults` under `dev.nwf.MoreCorners`.
- Uninstall: quit the app, delete `MoreCorners.app`, and run
  `defaults delete dev.nwf.MoreCorners`.
