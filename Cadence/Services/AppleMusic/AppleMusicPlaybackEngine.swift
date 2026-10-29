import Foundation
#if os(iOS)
import MediaPlayer

/// Plays Apple Music catalog songs through the system's application queue player.
///
/// The whole queue is handed to the system player, so songs keep advancing (and the lock screen
/// keeps working) while Cadence is in the background. It needs an Apple Music subscription.
final class AppleMusicPlaybackEngine {
    enum Event {
        case status(PlayerController.Status)
        case progress(current: TimeInterval, duration: TimeInterval)
        /// The system player moved to another song in the queue on its own.
        case currentIndex(Int)
    }

    var onEvent: ((Event) -> Void)?

    /// Connecting to the system player can take a while, so it waits until an Apple Music song
    /// first plays instead of holding up launch. Every use below comes after `start`, except
    /// `stop`, which checks `isActive` first.
    private lazy var player: MPMusicPlayerApplicationController = {
        let player = MPMusicPlayerController.applicationQueuePlayer
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportState() }
            },
            center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportIndex() }
            },
        ]
        return player
    }()
    private var queueIDs: [String] = []
    private var progressTimer: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var isActive = false

    // MARK: Transport

    func start(queue: [Track], at index: Int) {
        isActive = true
        queueIDs = queue.map(\.id)
        let descriptor = MPMusicPlayerStoreQueueDescriptor(storeIDs: queueIDs)
        descriptor.startItemID = queueIDs[index]
        player.setQueue(with: descriptor)
        onEvent?(.status(.loading))
        player.prepareToPlay { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    self.onEvent?(.status(.failed(.playback(.appleMusicUnavailable))))
                } else {
                    self.player.play()
                    self.startProgressUpdates()
                }
            }
        }
    }

    func play() {
        player.play()
        startProgressUpdates()
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval) {
        player.currentPlaybackTime = time
    }

    func skipToNext() {
        player.skipToNextItem()
    }

    func skipToPrevious() {
        if player.currentPlaybackTime > PlaybackPolicy.restartThreshold {
            player.skipToBeginning()
        } else {
            player.skipToPreviousItem()
        }
    }

    /// Adds a song right after the current one without restarting playback.
    func insertNext(_ track: Track) {
        // Kept in step with the system queue, so songs added later still report their position.
        let current = player.indexOfNowPlayingItem
        queueIDs.insert(track.id, at: queueIDs.indices.contains(current) ? current + 1 : queueIDs.count)
        player.perform(queueTransaction: { queue in
            let current = queue.items.firstIndex { $0 == self.player.nowPlayingItem }
            let anchor = current.map { queue.items[$0] }
            queue.insert(MPMusicPlayerStoreQueueDescriptor(storeIDs: [track.id]), after: anchor)
        }, completionHandler: { _, _ in })
    }

    /// Adds a song at `index` in the queue without restarting playback, such as just before
    /// Autoplay's songs.
    func insert(_ track: Track, at index: Int) {
        queueIDs.insert(track.id, at: min(max(index, 0), queueIDs.count))
        player.perform(queueTransaction: { queue in
            let anchor = queue.items.indices.contains(index - 1) ? queue.items[index - 1] : queue.items.last
            queue.insert(MPMusicPlayerStoreQueueDescriptor(storeIDs: [track.id]), after: anchor)
        }, completionHandler: { _, _ in })
    }

    /// Adds a song to the end of the queue without restarting playback.
    func append(_ track: Track) {
        queueIDs.append(track.id)
        player.perform(queueTransaction: { queue in
            queue.insert(MPMusicPlayerStoreQueueDescriptor(storeIDs: [track.id]), after: queue.items.last)
        }, completionHandler: { _, _ in })
    }

    /// Hands control back to another service's player.
    func stop() {
        guard isActive else { return }
        isActive = false
        player.stop()
        stopProgressUpdates()
    }

    // MARK: Reporting

    private func reportState() {
        guard isActive else { return }
        switch player.playbackState {
        case .playing, .seekingForward, .seekingBackward:
            onEvent?(.status(.playing))
            startProgressUpdates()
        case .paused, .interrupted:
            onEvent?(.status(.paused))
            reportProgress()
            stopProgressUpdates()
        case .stopped:
            onEvent?(.status(.ended))
            stopProgressUpdates()
        @unknown default:
            break
        }
    }

    private func reportIndex() {
        guard isActive else { return }
        let index = player.indexOfNowPlayingItem
        if queueIDs.indices.contains(index) {
            onEvent?(.currentIndex(index))
        }
        reportProgress()
    }

    private func reportProgress() {
        guard isActive else { return }
        let duration = player.nowPlayingItem?.playbackDuration ?? 0
        onEvent?(.progress(current: player.currentPlaybackTime, duration: duration))
    }

    private func startProgressUpdates() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: PlaybackPolicy.progressInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reportProgress() }
        }
    }

    private func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}
#else
/// macOS has no MediaPlayer queue player, and the Mac app never queues Apple Music songs, so
/// this stand-in only keeps `PlayerController` the same on both platforms.
final class AppleMusicPlaybackEngine {
    enum Event {
        case status(PlayerController.Status)
        case progress(current: TimeInterval, duration: TimeInterval)
        case currentIndex(Int)
    }

    var onEvent: ((Event) -> Void)?

    func start(queue: [Track], at index: Int) {}
    func play() {}
    func pause() {}
    func seek(to time: TimeInterval) {}
    func skipToNext() {}
    func skipToPrevious() {}
    func insertNext(_ track: Track) {}
    func insert(_ track: Track, at index: Int) {}
    func append(_ track: Track) {}
    func stop() {}
}
#endif
