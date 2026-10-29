import SwiftUI

/// Small differences between iOS and macOS, kept in one place so screens read the same on both.

extension EnvironmentValues {
    /// Whether there's room for wide layouts: a regular-width iPad window, or any Mac window.
    /// Size classes don't exist on macOS.
    var isWideLayout: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }
}

enum NavigationTitleStyle {
    case inline
    case large
}

enum PointerHover {
    case lift
    case highlight
}

extension View {
    /// The navigation bar's title style on iOS; Mac windows have no such setting.
    @ViewBuilder
    func navigationTitleStyle(_ style: NavigationTitleStyle) -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(style == .inline ? .inline : .large)
        #else
        self
        #endif
    }

    /// iPad pointer feedback; the Mac keeps its standard cursor.
    @ViewBuilder
    func pointerHover(_ effect: PointerHover) -> some View {
        #if os(iOS)
        switch effect {
        case .lift: hoverEffect(.lift)
        case .highlight: hoverEffect(.highlight)
        }
        #else
        self
        #endif
    }
}
