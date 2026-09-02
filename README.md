# MoreCorners

**Hot corners for macOS, without the limits.** A menu-bar utility that turns
your screen corners into 40+ configurable actions — with per-corner modifier
combos, multi-display awareness, and safeguards that keep corners from firing
when you don't want them to.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![Build](https://img.shields.io/badge/build-SwiftPM-brightgreen)

macOS ships four hot-corner actions and a single modifier per corner.
MoreCorners gives each corner a default action **plus** any number of
modifier-specific overrides (⌃, ⌥⇧, ⌘⌃…, matched exactly), drawn from a
catalog of 46 actions — including some macOS doesn't offer anywhere, like
moving the focused window to the next Space, tiling it to half the screen,
or muting your microphone.

## Highlights

- **46 actions in 6 groups** — spaces, window tiling, media, mic mute,
  capture, power, dark mode, and fully custom (shell, AppleScript,
  Shortcuts, keystrokes, apps, URLs).
- **Modifier overrides per corner** — one corner can do five different
  things depending on what you're holding.
- **Two trigger styles** — dwell (configurable delay and zone size, with a
  live on-screen preview of the trigger zones) or *push into the corner*
  for instant, macOS-style firing.
- **Multi-display native** — corners work on every display, only *exposed*
  corners of the combined desktop trigger (so crossing between monitors is
  safe), and menu-bar actions open on the display whose corner you hit.
- **Knows when to stay quiet** — pause from the menu (indefinitely or for
  15 min / 1 h / 2 h / until tomorrow, surviving relaunches), suppress in
  full-screen apps, exclude specific apps, and never fire at the lock
  screen or during drags.
- **Feedback you choose** — corner flash, sound, haptic tap, and an
  optional progress ring that shows what's about to fire while you dwell.
- **Safety nets** — optional confirmation before destructive actions,
  warnings when a macOS system hot corner overlaps yours, and a live
  Accessibility-permission indicator.
- **Portable settings** — JSON export/import, plus one-click reset to a
  sensible default layout.
- **Light footprint** — no event taps, no input monitoring; a single
  adaptive poll that idles when the pointer is nowhere near a corner and
  stops entirely while paused.

## Install

**Download:** grab `MoreCorners-<version>.dmg` from
[Releases](../../releases), open it, and drag **MoreCorners** to
Applications.

> **Gatekeeper note:** releases are currently signed with a development
> certificate, not notarized. On first launch, **right-click the app →
> Open** and confirm once (or run
> `xattr -dr com.apple.quarantine /Applications/MoreCorners.app`).

**Or build from source** (needs only the Xcode Command Line Tools):

```sh
git clone <this repo> && cd <repo>
./build.sh run
```

## Using it

On first launch the Settings window opens with a ready-to-use layout —
top corners for the Apple menu / Notification Center (with ⌃ to switch
Spaces and ⌥ to carry a window along), Quick Note bottom-left, Show
Desktop bottom-right. Change everything in the **Corners** tab; each row
has a ▶ button to try its action immediately.

The menu bar icon (a four-corner bracket mark) gives quick access to every
configured action, pause controls, Keep Awake, and Settings. It dims with
a slash while paused and gains a dot while Keep Awake is on. You can hide
the icon entirely for an invisible utility — to get Settings back, just
launch MoreCorners again (Finder, Spotlight, or `open -a MoreCorners`);
the running app reopens the window instead of starting a second copy.

### Corners and modifiers

Each corner has a **Default** action plus any number of **"While
holding…"** rows binding an exact modifier combination to its own action:

- Hit the corner → the Default runs.
- Hit it holding ⌘ (and a ⌘ row exists) → that action runs instead.
- Combos match *exactly*: ⌘⇧ does not trigger the ⌘ row.
- Leave Default as "None" and add overrides for a corner that only fires
  with modifiers held — it waits until the right ones are down.

### Actions

| Group | Actions |
|---|---|
| **Windows & Desktop** | Mission Control · Application Windows · Show Desktop · Launchpad/Apps · Control Center · Notification Center · Apple Menu · Quick Note · Next/Previous Space · Move App to Next/Previous Space · Move Window to Left/Right Half · Maximize Window · Center Window · Hide Frontmost App · Hide Others · Quit Frontmost App |
| **Display & Power** | Lock Screen · Screen Saver · Display Sleep · System Sleep · Toggle Keep Awake · Brightness Up/Down · Log Out |
| **Sound & Media** | Toggle Mute · Toggle Microphone Mute · Volume Up/Down · Play/Pause · Next/Previous Track |
| **Capture** | Screenshot Area → Clipboard · Screenshot Screen → Desktop |
| **System** | Toggle Dark Mode · Toggle Dock Auto-Hide · Empty Trash |
| **Open & Run** | Launch App · Open URL · Open File/Folder · Run Shell Command · Run AppleScript · Run Shortcuts Shortcut · Press Keyboard Shortcut |

Parameterized actions show a text field (with a file picker where it
helps). `Open URL` accepts a bare host like `example.com`. `Press
Keyboard Shortcut` takes specs like `cmd+shift+4`, `ctrl+left`, `f11`.
`Run Shortcuts Shortcut` runs any Shortcuts-app shortcut by name — handy
for things with no public API (Focus modes, HomeKit, …).

### Behavior options

**Triggering** — dwell delay (0–1 s) and corner size (2–24 px, with a
live preview of the zones while you drag the slider), or *activate by
pushing into the corner* for instant firing; per-corner on/off switches;
detect corners on all displays or just the main one.

**Staying out of the way** — pause from the menu (indefinite or timed,
with auto-resume that survives relaunches); pause automatically in
full-screen apps (video, games, presentations — detected without any
permissions); exclude specific apps by bundle ID; never fires while a
mouse button is down, at the lock screen, or during the screensaver;
after firing, the pointer must leave the corner before it can re-arm.

**Feedback** — corner flash, system sound (pick which), haptic tap, in
any combination; plus an optional dwell progress ring that names the
action about to fire, live-updating as you press modifiers (needs a
trigger delay of at least 0.15 s).

**Safety** — optional *Ask before destructive actions* (off by default)
puts a Run/Cancel confirmation in front of corner-triggered Quit App,
Empty Trash, and Log Out. The settings window also warns — with modifier
awareness — when a macOS system hot corner (System Settings → Desktop &
Dock) overlaps one of yours, and shows live whether the Accessibility
permission is granted.

**Housekeeping** — launch at login, hide the menu bar icon,
export/import settings as JSON (older exports stay loadable), reset to
defaults.

## Permissions

Corner detection needs **no permissions at all** — it polls the global
mouse position; there is no event tap and no input monitoring. Individual
actions request standard one-time grants:

| Permission | Needed by |
|---|---|
| Accessibility | Media keys, brightness, keystrokes, Control Center / Notification Center / Apple Menu / Quick Note, Space switching and window moves, window tiling |
| Automation (System Events / Finder) | Toggle Dark Mode, Empty Trash, Log Out |
| Screen Recording | Screenshot actions (macOS prompts via `screencapture`); **also Move App to Next/Previous Space** — see below |

Quick Note and Notification Center synthesize the built-in globe
shortcuts (fn+Q / fn+N), so those must remain enabled in System Settings
→ Keyboard.

**Move App to Next/Previous Space needs Screen Recording** (in addition to
Accessibility). It holds the window with a genuine window-server drag, and
macOS gates one process driving another app's windows behind the Screen
Recording grant — nothing is ever recorded. Without it the move beeps and
logs a hint instead of moving the window. When one of these actions is
configured, the Behavior tab shows the Screen Recording status live, with a
one-click button to the right pane; the row stays hidden otherwise, so the
permission is only ever asked for when it's actually needed.

## Building & development

```sh
./build.sh run    # build MoreCorners.app and (re)launch it
./build.sh app    # build the bundle only (fast dev loop)
./build.sh        # build the bundle AND package MoreCorners-<version>.dmg
make              # make build / app / dmg / run / icon / clean
open Package.swift   # full edit/run/test in Xcode — no project file needed
```

Shell builds need only the Command Line Tools. `build.sh` signs with your
Apple Development certificate when one is in the keychain (override with
`CODESIGN_IDENTITY=<hash-or-name>`); developer-cert TCC grants are keyed
to team + bundle ID, so **permissions survive rebuilds**. With no
certificate it falls back to ad-hoc signing (permissions reset each
rebuild — the build output warns). `make icon` regenerates
`AppIcon.icns` from `scripts/make-icon.swift`.

The logic lives in a `MoreCornersCore` library so it can be unit tested;
the `MoreCorners` executable is a three-line `main.swift` that calls into
it:

```
Sources/MoreCorners/main.swift        # executable entry point
Sources/MoreCornersCore/*.swift       # all app logic (library)
Tests/MoreCornersCoreTests/*.swift    # XCTest suite
```

### Tests

```sh
# XCTest ships with Xcode, not the Command Line Tools — if your active
# toolchain is the CLT, point DEVELOPER_DIR at a full Xcode install:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

**Unit tests** (always run) cover the pure logic: action resolution and
modifier matching, catalog invariants, corner geometry and the
exposed-edge check, the dwell/re-arm state machine, window-tiling
geometry, timed-pause restoration, settings migration and round-trips,
and the key-spec / symbolic-hotkey parsers.

**An end-to-end harness** (`ActionIntegrationTests`, opt-in via
`MORECORNERS_E2E=1`) actually fires every assignable action once per
connected display, in both focused- and unfocused-display states,
asserting the effects observable from public APIs and printing a manual
checklist for the rest. It is skipped by default because it drives real
system UI; destructive actions additionally require
`MORECORNERS_E2E_DESTRUCTIVE=1`, and `MORECORNERS_E2E_ONLY=a,b,c`
restricts the run. The test runner needs its own Accessibility (and
Screen Recording) grants; ungranted cases are skipped with a note.

### Releasing

`./build.sh` (or `make dmg`) packages a compressed drag-to-install
`MoreCorners-<version>.dmg` (app + `/Applications` alias), ready to
attach to a GitHub release; the artifact is gitignored. Releases are not
yet notarized — that requires a paid Apple Developer account (sign with a
Developer ID Application certificate via `CODESIGN_IDENTITY`, then
`xcrun notarytool submit --wait` and `xcrun stapler staple`).

## How it works

Some of the techniques are unusual enough to be worth documenting:

- **Mission Control / Application Windows / Show Desktop** are driven via
  `CoreDockSendNotification` — the private notification API the Dock
  itself listens on. It keeps working across macOS releases where the
  Mission Control binary moved and synthesized ⌃-arrow shortcuts broke,
  and needs no Accessibility permission.
- **Space switching** posts synthetic trackpad *dock-swipe gestures*
  rather than keyboard shortcuts, so it works regardless of your Mission
  Control keyboard settings and acts on the display under the pointer. On
  macOS 27+ these gestures must carry a serialized IOHID payload in
  CGEvent field 4205 (technique shared with the author's SpacesMenu app).
- **Move App to Next/Previous Space** "holds" the focused window with a
  genuine server-side drag (`SLSDragWindowRelativeToMouse`, private
  SkyLight SPI — the private `CGSMoveWindowsToManagedSpace` teleport call
  silently no-ops for unentitled apps on macOS 26+) and fires your actual
  "Move a space" binding, read live from `com.apple.symbolichotkeys`
  (remapped chords included) — the held window rides across. The window is
  named by its window-server ID, so **nothing on it has to be clickable**:
  a window with a toolbar'd title bar, or one parked off-screen, moves as
  easily as any other. The synthetic mouse-down the drag binds to lands on
  a private invisible overlay (the pointer is at a hot corner, so a down
  there would open a menu). The move is verified against the window server
  and beeps + logs if the window didn't land — the usual cause being a
  missing Screen Recording grant (see Permissions). This mechanism is
  ported from the author's WindowShift project, which replaced its own
  earlier synthetic-title-bar-grab technique the same way.
- **Coexisting with other space managers**: an app with an event tap on
  the space-switch chord (e.g. SpacesMenu) would swallow the shortcut
  mid-drag. MoreCorners posts `dev.nwf.MoreCorners.windowMoveBegan`/
  `…Ended` distributed notifications around each move so a peer can stand
  its tap down (with a self-clearing 3 s safety flag). Neither app
  depends on the other; the signal is ignored if nobody listens.
- **Window tiling** (halves / maximize / center) sets the focused
  window's frame through the Accessibility API within its display's
  visible area.
- **Microphone mute** talks CoreAudio directly to the default input
  device — its native mute control when present, else zeroing and
  restoring the input volume. No permissions needed.
- **Multi-display menu-bar actions** open on the display whose corner you
  hit: the app hit-tests that display's own menu bar (menu extras are
  laid out identically on every display) and clicks the equivalent spot,
  restoring the pointer afterward — nudged just outside the trigger zone
  so the warp-back can't re-fire the corner. Globe-shortcut panels
  (Notification Center, Quick Note) first pull the "active display" over
  with a brief synthetic click on an invisible helper window, because
  programmatic activation alone doesn't move it. (Requires "Displays have
  separate Spaces".)
- **Full-screen detection** uses the window list only (no permissions),
  distinguishing true full-screen from a merely maximized window by
  whether the menu-bar strip is covered.
- **Lock Screen** calls `SACLockScreenImmediate` from the private login
  framework — the approach common utilities use.
- **Adaptive polling**: the mouse-position poll runs at 50 ms only while
  the pointer is within 300 pt of an exposed corner (or a dwell is in
  progress), relaxes to 120 ms otherwise, stops entirely while paused,
  and drops to a 2 s heartbeat at the lock screen (lock/unlock
  notifications wake it immediately).

Settings persist in `defaults` under `dev.nwf.MoreCorners`.

## Uninstall

Quit the app, delete `MoreCorners.app`, and run
`defaults delete dev.nwf.MoreCorners`.
