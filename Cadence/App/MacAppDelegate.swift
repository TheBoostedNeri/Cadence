#if os(macOS)
import AppKit
import SwiftUI

/// Closing the window hides it and Cadence stays open, so music keeps playing, as it does in Music.
/// The window is hidden rather than closed because closing it tears down the view holding the
/// YouTube player, and WebKit pauses a player that leaves its window. Clicking the Dock icon
/// brings the window back; Quit still quits.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// The main window, once it has been told to hide on close.
    private weak var mainWindow: NSWindow?
    private var hidingDelegate: HidingWindowDelegate?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, let mainWindow else { return true }
        mainWindow.makeKeyAndOrderFront(nil)
        return false
    }

    fileprivate func hideOnClose(_ window: NSWindow) {
        mainWindow = window
        guard !(window.delegate is HidingWindowDelegate) else { return }
        let delegate = HidingWindowDelegate(wrapping: window.delegate)
        hidingDelegate = delegate
        window.delegate = delegate
    }
}

/// Stands in for SwiftUI's window delegate, hiding the window instead of closing it and passing
/// everything else through to SwiftUI's.
private final class HidingWindowDelegate: NSObject, NSWindowDelegate {
    nonisolated(unsafe) private weak var original: (any NSWindowDelegate)?
    private var fullScreenExit: (any NSObjectProtocol)?

    init(wrapping original: (any NSWindowDelegate)?) {
        self.original = original
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // A full-screen window leaves an empty space behind, so it leaves full screen first.
        if sender.styleMask.contains(.fullScreen) {
            fullScreenExit = NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification, object: sender, queue: .main
            ) { [weak self, weak sender] _ in
                MainActor.assumeIsolated {
                    sender?.orderOut(nil)
                    if let self, let fullScreenExit = self.fullScreenExit {
                        NotificationCenter.default.removeObserver(fullScreenExit)
                        self.fullScreenExit = nil
                    }
                }
            }
            sender.toggleFullScreen(nil)
        } else {
            sender.orderOut(nil)
        }
        return false
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? { original }
}

/// Finds the window it's placed in and tells the app delegate to hide that window on close.
struct HidesWindowOnClose: NSViewRepresentable {
    let appDelegate: MacAppDelegate

    func makeNSView(context: Context) -> WindowFinder { WindowFinder(appDelegate: appDelegate) }
    func updateNSView(_ view: WindowFinder, context: Context) {}

    final class WindowFinder: NSView {
        private let appDelegate: MacAppDelegate

        init(appDelegate: MacAppDelegate) {
            self.appDelegate = appDelegate
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { appDelegate.hideOnClose(window) }
        }
    }
}
#endif
