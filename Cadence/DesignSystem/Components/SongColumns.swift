import SwiftUI

/// Songs in columns of a few rows, swiped through sideways, like Apple Music's Top Songs.
/// Each column is as wide as the page minus a peek of the next one, or a fixed width in wide
/// windows where several fit.
struct SongColumns<Row: View>: View {
    let tracks: [Track]
    /// The width of the page the columns scroll across.
    let pageWidth: CGFloat
    @ViewBuilder let row: (_ index: Int, _ track: Track) -> Row

    @Environment(\.isWideLayout) private var isWideLayout

    private var columnWidth: CGFloat {
        isWideLayout ? Layout.wideSongColumnWidth : max(0, pageWidth - Spacing.large * 2 - Layout.carouselPeek)
    }

    var body: some View {
        let rows = Array(
            repeating: GridItem(.fixed(ArtworkSize.row), spacing: Spacing.medium),
            count: Layout.songColumnRows
        )
        ScrollView(.horizontal) {
            LazyHGrid(rows: rows, spacing: Spacing.large) {
                // By position: charts can list the same song twice.
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    row(index, track)
                        .frame(width: columnWidth)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Spacing.large, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }
}
