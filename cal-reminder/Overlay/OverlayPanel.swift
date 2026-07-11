import AppKit

/// A borderless, always-on-top panel that draws the Overlay animation above every
/// window (including fullscreen), on every Space, without stealing focus (RNF-02).
/// Click-through by default; `DefaultOverlayAnimator` flips `ignoresMouseEvents` off
/// only while a flight is in progress, so a click can skip it (RF-09).
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
