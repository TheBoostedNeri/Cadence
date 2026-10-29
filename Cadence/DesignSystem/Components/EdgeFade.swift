import SwiftUI

extension View {
    /// Fades content out toward the top and bottom instead of clipping it hard, e.g. where a
    /// scroll view meets a view above it. A length of zero leaves that edge untouched.
    func edgeFade(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        mask {
            // Mask colors only set opacity: black keeps content, clear hides it.
            VStack(spacing: Spacing.none) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: top)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: bottom)
            }
            // Cover a view that extends into the safe area too, or that strip would be hidden.
            .ignoresSafeArea()
        }
    }

    /// Fades both edges by the same length.
    func edgeFade(length: CGFloat) -> some View {
        edgeFade(top: length, bottom: length)
    }
}
