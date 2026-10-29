import Foundation
import Observation

/// Which music service is active, and its catalog. Switching services resets library data so
/// no screen shows one service's playlists under another's name.
@Observable
final class ServiceHub {
    private(set) var current: MusicService

    @ObservationIgnored let youtube: YouTubeAPIClient
    #if os(iOS)
    @ObservationIgnored let appleMusic: AppleMusicCatalog
    #endif
    @ObservationIgnored var onServiceChanged: (() -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    #if os(iOS)
    init(youtube: YouTubeAPIClient, appleMusic: AppleMusicCatalog, defaults: UserDefaults = .standard) {
        self.youtube = youtube
        self.appleMusic = appleMusic
        self.defaults = defaults
        current = Self.storedService(in: defaults)
    }
    #else
    init(youtube: YouTubeAPIClient, defaults: UserDefaults = .standard) {
        self.youtube = youtube
        self.defaults = defaults
        current = Self.storedService(in: defaults)
    }
    #endif

    private static func storedService(in defaults: UserDefaults) -> MusicService {
        let stored = defaults.string(forKey: StorageKey.musicService).flatMap(MusicService.init(rawValue:))
        return stored.flatMap { $0.isAvailable ? $0 : nil } ?? .youtube
    }

    var catalog: any MusicCatalog {
        switch current {
        case .youtube, .spotify: youtube
        case .appleMusic:
            #if os(iOS)
            appleMusic
            #else
            youtube
            #endif
        }
    }

    /// Changes whenever the service or its connection does; screens reload on it.
    var connectionKey: ServiceConnectionKey {
        ServiceConnectionKey(service: current, isConnected: catalog.isConnected)
    }

    func select(_ service: MusicService) {
        guard service.isAvailable, service != current else { return }
        current = service
        defaults.set(service.rawValue, forKey: StorageKey.musicService)
        onServiceChanged?()
    }
}

struct ServiceConnectionKey: Hashable {
    let service: MusicService
    let isConnected: Bool
}
