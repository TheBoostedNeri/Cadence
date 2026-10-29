import SwiftUI

/// Menu bar items and keyboard shortcuts for iPad with a hardware keyboard.
struct AppCommands: Commands {
    let player: PlayerController
    let router: AppRouter

    var body: some Commands {
        CommandMenu("Playback") {
            // Text fields still get the space bar while someone is typing.
            Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Next Song") { player.next() }
                .keyboardShortcut(.rightArrow)
            Button("Previous Song") { player.previous() }
                .keyboardShortcut(.leftArrow)
            Divider()
            Button(player.isShuffled ? "Turn Off Shuffle" : "Shuffle") { player.toggleShuffle() }
                .disabled(!player.supportsShuffleAndRepeat)
            Button(repeatTitle) { player.cycleRepeatMode() }
                .disabled(!player.supportsShuffleAndRepeat)
            Button(player.isAutoplayEnabled ? "Turn Off Autoplay" : "Autoplay") { player.toggleAutoplay() }
            Divider()
            Button("Show Now Playing") { player.presentNowPlaying() }
                .keyboardShortcut("l")
            Button("Go to Album") {
                if let track = player.currentTrack { router.showAlbum(for: track) }
            }
            .disabled(player.currentTrack == nil)
            Button("Go to Artist") {
                if let track = player.currentTrack { router.showArtist(for: track) }
            }
            .disabled(player.currentTrack == nil)
        }
        CommandGroup(before: .sidebar) {
            Button("Home") { router.selectedTab = .home }
                .keyboardShortcut("1")
            Button("Discover") { router.selectedTab = .discover }
                .keyboardShortcut("2")
            Button("Playlists") { router.selectedTab = .playlists }
                .keyboardShortcut("3")
            Button("Recently Played") { router.selectedTab = .recents }
                .keyboardShortcut("4")
            Button("Search") { router.selectedTab = .search }
                .keyboardShortcut("f")
            Divider()
        }
    }

    /// Names what choosing it does next: off, then the whole queue, then one song.
    private var repeatTitle: LocalizedStringKey {
        switch player.repeatMode {
        case .off: "Repeat All"
        case .all: "Repeat One"
        case .one: "Turn Off Repeat"
        }
    }
}
