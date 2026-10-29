import SwiftUI

/// A page of songs under a header, like a playlist, album or artist. Wide windows keep the
/// header beside the songs, like Apple Music on iPad; elsewhere it scrolls above them.
struct SongListPage<Header: View, Rows: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let rows: Rows
    @Environment(\.isWideLayout) private var isWideLayout

    var body: some View {
        if isWideLayout {
            HStack(alignment: .top, spacing: Spacing.none) {
                ScrollView {
                    header
                        .padding(.horizontal, Spacing.large)
                }
                .frame(width: Layout.detailHeaderColumnWidth)
                songList { rows }
            }
        } else {
            songList {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                rows
            }
        }
    }

    private func songList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        List { content() }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
    }
}

/// Play and Shuffle side by side, for the header of a song list.
struct PlayShuffleButtons: View {
    let play: (_ shuffled: Bool) -> Void

    var body: some View {
        GlassEffectContainer(spacing: Spacing.medium) {
            HStack(spacing: Spacing.medium) {
                // Lists tint label icons with the accent color, which would hide the
                // icon on the brand-colored button, so both colors are set explicitly.
                Button { play(false) } label: {
                    Label("Play", systemImage: "play.fill")
                        .foregroundStyle(Palette.onBrand)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                Button { play(true) } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
    }
}
