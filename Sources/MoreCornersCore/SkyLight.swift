import CoreGraphics

/// Binding to the one SkyLight symbol the space-move needs — ported from the
/// WindowShift project, where the mechanism was established and measured.
///
/// `SLSDragWindowRelativeToMouse` starts a genuine server-side drag of an
/// arbitrary window named by its `CGWindowID` — the same kind of session the
/// window server runs for a manual title-bar drag — without anything having to
/// click the title bar. MoreCorners uses it to "hold" the focused window while
/// the native "Move a space" shortcut fires, so the window rides across to the
/// adjacent Space. This replaces the old synthetic title-bar grab, which
/// needed a safe clickable point (absent on windows with toolbar'd title bars
/// or title bars parked off-screen).
///
/// The contract, established by WindowShift's testing and re-verified here:
///  - a real `leftMouseDown` must already have LANDED; with no button down the
///    call succeeds and does nothing,
///  - `offset` is the cursor relative to the window's origin at the moment the
///    button went down (CG top-left coordinates),
///  - the window tracks the drag EVENT STREAM, not the hardware cursor — post
///    no drags and it stays put, which is exactly what the space-move wants,
///  - ending the drag means ending the button (the SPI's cancel is a no-op),
///  - the cross-process hand-over is gated on the **Screen Recording** grant:
///    without it the call reports success and the window is never bound.
///
/// It is private API, resolved at runtime: a future macOS could remove it or
/// gate it like `SLSMoveWindow` (the discrete-teleport call) already is.
/// `available` is the check every caller must make.
enum SkyLight {
    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias DragRelFn = @convention(c) (Int32, UInt32, CGPoint) -> Int32

    private static let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    private static let mainConnectionID = sym("SLSMainConnectionID", MainConnFn.self)
    private static let dragWindowRelativeToMouse =
        sym("SLSDragWindowRelativeToMouse", DragRelFn.self)

    /// Whether the mechanism is usable at all on this system.
    static var available: Bool { mainConnectionID != nil && dragWindowRelativeToMouse != nil }

    /// Bind the mouse button that is currently down to a server-side drag of
    /// `window`. Returns false when the SPI is missing or reports an error.
    @discardableResult
    static func beginDrag(window: CGWindowID, offset: CGPoint) -> Bool {
        guard let mainConnectionID, let dragWindowRelativeToMouse else { return false }
        return dragWindowRelativeToMouse(mainConnectionID(), window, offset) == 0
    }
}
