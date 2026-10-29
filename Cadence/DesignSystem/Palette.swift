import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Semantic colors. Every token resolves separately for light and dark appearance.
enum Palette {
    /// Brand color, defined once in Assets.xcassets/AccentColor with light and dark variants.
    static let brand = Color.accentColor
    /// Text and icons drawn on brand-colored surfaces, such as prominent buttons.
    static let onBrand = Color.white
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let backgroundTop = Color(light: 0xF3F0FF, dark: 0x17132B)
    #if os(iOS)
    static let backgroundBottom = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .systemBackground)
    static let artworkPlaceholder = Color(uiColor: .tertiarySystemFill)
    /// Raised cards on a page, like an artist's latest release.
    static let cardFill = Color(uiColor: .tertiarySystemFill)
    /// Controls with nothing to act on, like the mini player's buttons with nothing playing.
    static let textDisabled = Color(uiColor: .tertiaryLabel)
    #else
    static let backgroundBottom = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let artworkPlaceholder = Color(nsColor: .tertiarySystemFill)
    static let cardFill = Color(nsColor: .tertiarySystemFill)
    static let textDisabled = Color(nsColor: .tertiaryLabelColor)
    #endif
    static let playerBackground = Color.black
    static let onPlayer = Color.white
    static let scrim = Color.black.opacity(Opacity.scrim)
    static let backdropDim = Color.black.opacity(Opacity.backdropDim)
    /// Behind Now Playing's selected buttons and pressed controls.
    static let controlFill = Color.primary.opacity(Opacity.controlFill)
    static let shadow = Color.black.opacity(Opacity.shadow)
    static let inactive = Color.secondary.opacity(Opacity.inactive)
    static let success = Color.green
    static let warning = Color.orange
    static let destructive = Color.red
    /// Discover's genre tiles take these in turn, like Apple Music's colorful Browse tiles.
    static let genreTints: [Color] = [.pink, .orange, .purple, .blue, .teal, .red, .indigo, .green, .mint, .cyan, .brown]

    static let backgroundGradient = LinearGradient(
        colors: [backgroundTop, backgroundBottom],
        startPoint: .top,
        endPoint: .center
    )
}

extension Color {
    /// A color that switches between two sRGB hex values based on the current appearance.
    init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            NSColor(hex: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
        #endif
    }
}

#if os(iOS)
private typealias PlatformColor = UIColor
#else
private typealias PlatformColor = NSColor
#endif

private extension PlatformColor {
    convenience init(hex: UInt32) {
        let channelMax: CGFloat = 255
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / channelMax,
            green: CGFloat((hex >> 8) & 0xFF) / channelMax,
            blue: CGFloat(hex & 0xFF) / channelMax,
            alpha: 1
        )
    }
}
