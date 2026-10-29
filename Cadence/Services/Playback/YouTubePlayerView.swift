import SwiftUI
import WebKit
#if os(iOS)
import UIKit

/// Holds the player and never takes a touch itself or lets one through to it: the app's own
/// controls drive playback, and YouTube's overlay must never appear.
final class PlayerContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
}
#else
import AppKit

/// Holds the player and never takes a click itself or lets one through to it. On the Mac,
/// SwiftUI's `allowsHitTesting(false)` doesn't stop a hosted web view from catching clicks, so
/// with background play on, the nearly invisible player swallowed clicks on the content it sat
/// over. Clicks now fall through to whatever is beneath.
final class PlayerContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif

/// Hosts the single long-lived player web view so playback state survives re-presentation.
struct YouTubePlayerView {
    let webView: WKWebView
    /// Called after the player moves into this view from somewhere else.
    var onAttach: () -> Void = {}

    private func makeContainer() -> PlayerContainerView {
        let container = PlayerContainerView()
        // The player never draws, or reaches, past the spot it's given.
        container.clipsToBounds = true
        #if os(iOS)
        container.backgroundColor = UIColor(Palette.playerBackground)
        #else
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(Palette.playerBackground).cgColor
        #endif
        return container
    }

    private func attachWebView(to container: PlayerContainerView) {
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        #if os(iOS)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #else
        webView.autoresizingMask = [.width, .height]
        #endif
        container.addSubview(webView)
        onAttach()
    }
}

#if os(iOS)
extension YouTubePlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerContainerView { makeContainer() }
    func updateUIView(_ container: PlayerContainerView, context: Context) { attachWebView(to: container) }
}
#else
extension YouTubePlayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> PlayerContainerView { makeContainer() }
    func updateNSView(_ container: PlayerContainerView, context: Context) { attachWebView(to: container) }
}
#endif
