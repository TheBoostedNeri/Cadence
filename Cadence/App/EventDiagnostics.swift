#if DEBUG && os(macOS)
import AppKit
import ObjectiveC
import OSLog
import SwiftData

// TEMPORARY: records where real clicks and scrolls go, to find the part of the Mac window that
// stops responding while a song plays. Read with:
//   log show --last 10m --style compact --predicate 'subsystem == "com.nerijus.cadence.diagnostics"'
// Remove once the bug is fixed.
enum EventDiagnostics {
    private static let logger = Logger(subsystem: "com.nerijus.cadence.diagnostics", category: "events")
    private static var monitors: [Any] = []

    /// With CADENCE_DIAG_PLAY set, plays a short video muted, then restores the volume and quits.
    static func playIfRequested(_ environment: AppEnvironment) {
        guard ProcessInfo.processInfo.environment["CADENCE_DIAG_PLAY"] != nil else { return }
        Task { @MainActor in
            let player = environment.player
            let volume = player.volume
            try? await Task.sleep(for: .seconds(3))
            player.setVolume(0)
            player.play([Track(id: "jNQXAC9IVRw", title: "Diagnostics", artist: "Diagnostics", artworkURL: nil, largeArtworkURL: nil, duration: 19)])
            logger.notice("diag play started")
            try? await Task.sleep(for: .seconds(40))
            player.pause()
            player.setVolume(volume)
            let context = environment.modelContainer.mainContext
            try? context.delete(model: RecentPlay.self, where: #Predicate { $0.videoID == "jNQXAC9IVRw" })
            try? context.save()
            exit(0)
        }
    }

    static func start() {
        guard monitors.isEmpty else { return }
        watchIgnoresMouseEvents()
        // Events Cadence receives.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel, .rightMouseDown], handler: { event in
            MainActor.assumeIsolated { record(event, deliveredToCadence: true) }
            return event
        }) {
            monitors.append(local)
        }
        // Clicks that go to another app instead, e.g. because a window is lying on top.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .scrollWheel], handler: { event in
            MainActor.assumeIsolated { record(event, deliveredToCadence: false) }
        }) {
            monitors.append(global)
        }
        logger.notice("diagnostics started")
    }

    private static func record(_ event: NSEvent, deliveredToCadence: Bool) {
        // One line per scroll gesture: its start on a trackpad, or each tick of a mouse wheel.
        if event.type == .scrollWheel {
            let isWheelTick = event.phase == [] && event.momentumPhase == []
            guard event.phase == .began || isWheelTick else { return }
        }
        let screenPoint = NSEvent.mouseLocation
        guard let window = NSApp.windows.filter({ $0.isVisible })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let content = window.contentView, let frameView = content.superview
        else {
            logger.notice("\(event.type.rawValue) no window")
            return
        }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let inWindow = window.frame.contains(screenPoint)
        var line = "\(deliveredToCadence ? "CADENCE" : "OTHER-APP") type=\(event.type.rawValue) "
            + "window=(\(Int(windowPoint.x)),\(Int(windowPoint.y))) inWindow=\(inWindow) "
            + "key=\(window.isKeyWindow) active=\(NSApp.isActive) eventWindow=\(event.windowNumber) ours=\(window.windowNumber)"
        line += " ignoresMouse=\(window.ignoresMouseEvents) opaque=\(window.isOpaque) alpha=\(window.alphaValue)"
            + " bgAlpha=\(window.backgroundColor.alphaComponent) level=\(window.level.rawValue) style=\(window.styleMask.rawValue)"
        if inWindow, let hit = frameView.hitTest(frameView.convert(windowPoint, from: nil)) {
            line += " hit=\(type(of: hit)) \(NSStringFromRect(hit.convert(hit.bounds, to: nil)))"
        }
        if !deliveredToCadence || !inWindow {
            line += " above=" + windowsAbove(window).joined(separator: "; ")
        }
        logger.notice("\(line, privacy: .public)")
    }

    /// Logs every change to a window's "ignores mouse events" setting, with who changed it.
    private static func watchIgnoresMouseEvents() {
        let selector = #selector(setter: NSWindow.ignoresMouseEvents)
        guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
        typealias Setter = @convention(c) (NSWindow, Selector, Bool) -> Void
        let original = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        let replacement: @convention(block) (NSWindow, Bool) -> Void = { window, ignores in
            let caller = Thread.callStackSymbols.prefix(14).joined(separator: " | ")
            Logger(subsystem: "com.nerijus.cadence.diagnostics", category: "events")
                .notice("setIgnoresMouseEvents(\(ignores)) on \(type(of: window), privacy: .public) '\(window.title, privacy: .public)' from: \(caller, privacy: .public)")
            original(window, selector, ignores)
        }
        method_setImplementation(method, imp_implementationWithBlock(replacement))
    }

    private static func windowsAbove(_ window: NSWindow) -> [String] {
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow], CGWindowID(window.windowNumber)) as? [[String: Any]] ?? []
        return infos.map { info in
            let owner = info[kCGWindowOwnerName as String] as? String ?? "?"
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            let bounds = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
            return "\(owner) layer=\(layer) \(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0)) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))"
        }
    }
}
#endif
