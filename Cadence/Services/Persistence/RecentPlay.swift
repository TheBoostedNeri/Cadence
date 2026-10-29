import Foundation
import SwiftData

/// A track the user played on this device. One row per video, updated on each play.
@Model
final class RecentPlay {
    @Attribute(.unique) var videoID: String
    var title: String
    var artist: String
    var artworkURL: URL?
    var largeArtworkURL: URL?
    var duration: TimeInterval?
    var lastPlayedAt: Date
    var playCount: Int
    /// The `MusicService` raw value. The default lets existing history migrate as YouTube.
    var source: String = MusicService.youtube.rawValue

    init(track: Track, playedAt: Date) {
        videoID = track.id
        title = track.title
        artist = track.artist
        artworkURL = track.artworkURL
        largeArtworkURL = track.largeArtworkURL
        duration = track.duration
        lastPlayedAt = playedAt
        playCount = 1
        source = track.source.rawValue
    }

    func recordPlay(of track: Track, at date: Date) {
        title = track.title
        artist = track.artist
        artworkURL = track.artworkURL
        largeArtworkURL = track.largeArtworkURL
        duration = track.duration
        lastPlayedAt = date
        playCount += 1
    }

    var track: Track {
        Track(
            id: videoID,
            title: title,
            artist: artist,
            artworkURL: artworkURL,
            largeArtworkURL: largeArtworkURL,
            duration: duration,
            source: MusicService(rawValue: source) ?? .youtube
        )
    }
}

/// Writes play history. Reading happens through `@Query` in the views.
final class RecentsStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Failures are ignored on purpose: losing a history entry must never interrupt playback.
    func record(_ track: Track, at date: Date = .now) {
        let videoID = track.id
        var descriptor = FetchDescriptor<RecentPlay>(predicate: #Predicate { $0.videoID == videoID })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.recordPlay(of: track, at: date)
        } else {
            context.insert(RecentPlay(track: track, playedAt: date))
        }
        try? context.save()
        trimHistory()
    }

    /// Runs after the new play is saved: the fetch offset skips only saved rows, so an unsaved
    /// play would come back as "overflow" and be deleted straight away.
    private func trimHistory() {
        var descriptor = FetchDescriptor<RecentPlay>(sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
        descriptor.fetchOffset = RecentsPolicy.maxEntries
        guard let overflow = try? context.fetch(descriptor), !overflow.isEmpty else { return }
        for play in overflow {
            context.delete(play)
        }
        try? context.save()
    }
}

extension ModelContainer {
    static func recents(inMemory: Bool) -> ModelContainer {
        let schema = Schema([RecentPlay.self])
        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            )
        } catch {
            // A damaged store must not stop the app from launching: keep history for this session only.
            do {
                return try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("Could not create an in-memory SwiftData store: \(error)")
            }
        }
    }
}
