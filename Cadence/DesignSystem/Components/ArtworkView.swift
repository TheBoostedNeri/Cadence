import SwiftUI

/// Remote artwork cropped to fill its frame, with a symbol placeholder while loading or on failure.
struct ArtworkView: View {
    let url: URL?
    /// Square side length; `nil` fills the proposed space.
    var size: CGFloat?
    var cornerRadius: CGFloat = Radius.small
    var placeholderSymbol = "music.note"

    var body: some View {
        Rectangle()
            .fill(Palette.artworkPlaceholder)
            .overlay {
                AsyncImage(url: url, transaction: Transaction(animation: Motion.quick)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: placeholderSymbol)
                            .font(.system(size: (size ?? ArtworkSize.header) * Layout.placeholderSymbolScale))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: cornerRadius))
            // Clipping hides the image's overflow but still lets it take clicks and taps. A cover
            // filling a tall, narrow frame spills far past its sides, and Now Playing's backdrop
            // spilled over the middle of the app, so nothing there could be clicked.
            .contentShape(.rect(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}
