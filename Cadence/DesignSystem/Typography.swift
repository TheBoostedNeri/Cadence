import SwiftUI

/// Text styles built on Dynamic Type so they scale with the user's preferred size.
enum Typography {
    static let display = Font.largeTitle.weight(.bold)
    static let title = Font.title2.weight(.bold)
    static let sectionTitle = Font.title3.weight(.semibold)
    static let headline = Font.headline
    static let body = Font.body
    static let rowTitle = Font.body.weight(.medium)
    static let rowSubtitle = Font.subheadline
    static let cardTitle = Font.subheadline.weight(.semibold)
    static let footnote = Font.footnote
    static let caption = Font.caption
    static let monospacedCaption = Font.caption.monospacedDigit()
    static let miniPlayerTitle = Font.subheadline.weight(.semibold)
    static let miniPlayerSubtitle = Font.caption
    static let miniPlayerControl = Font.title3
    /// The Mac player bar: Play stands out, Shuffle and Repeat recede.
    static let barPrimaryControl = Font.title
    static let barControl = Font.title2
    static let barSecondaryControl = Font.body
    static let displayTitle = Font.headline
    static let displaySubtitle = Font.subheadline
    static let transportPrimary = Font.system(size: IconSize.transportPrimary)
    static let transportSecondary = Font.system(size: IconSize.transportSecondary)
    /// Now Playing's song and artist, like Apple Music's.
    static let nowPlayingTitle = Font.title3.weight(.semibold)
    static let nowPlayingArtist = Font.title3
    static let headerIcon = Font.subheadline.weight(.semibold)
    /// The artist's name over their page's header, and its Play button.
    static let artistName = Font.largeTitle.weight(.bold)
    static let headerPlay = Font.title2.weight(.semibold)
    /// Lyrics, AirPlay and Up Next along the bottom of Now Playing.
    static let nowPlayingAccessory = Font.title2
    static let heroSymbol = Font.system(size: IconSize.xLarge, weight: .semibold)
    static let chartRank = Font.headline.monospacedDigit()
    /// The circles beside songs while picking several.
    static let selectionMark = Font.title3
    /// Discover's genre tiles.
    static let genreTileTitle = Font.headline.weight(.bold)
    static let genreTileSymbol = Font.system(size: IconSize.xLarge, weight: .semibold)
    static let trackNumber = Font.body.monospacedDigit()
    static let badge = Font.caption2.weight(.semibold)
    static let greeting = Font.title2.weight(.bold)
    static let sectionAction = Font.subheadline.weight(.semibold)
    /// Synced lyrics: large and bold, like Apple Music's.
    static let lyric = Font.largeTitle.weight(.bold)
    static let plainLyrics = Font.title2.weight(.semibold)
}
