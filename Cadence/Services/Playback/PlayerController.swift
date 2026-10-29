import AVFoundation
import Foundation
import Observation
import WebKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Owns the play queue and routes playback to the right service: the embedded YouTube player or
/// the system Apple Music player. A queue always plays through a single service.
///
/// YouTube's API policies require its player to stay visible while it plays, so by default YouTube
/// playback only runs while Now Playing is on screen and pauses when it is dismissed or the app goes
/// to the background. The experimental (unofficial) background-play setting lifts that for personal
/// use. Apple Music has no such limit and keeps playing.
@Observable
final class PlayerController {
    enum Status: Equatable {
        case idle
        case loading
        case buffering
        case playing
        case paused
        case ended
        case failed(AppError)
    }

    enum RepeatMode {
        case off
        /// Back to the first song after the last.
        case all
        /// The current song over and over.
        case one
    }

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var status: Status = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// The YouTube player's own volume, from 0 to 1. The Mac sets it from the toolbar; iPhone and
    /// iPad leave it full and use the device volume.
    private(set) var volume = PlaybackPolicy.fullVolume
    private(set) var isShuffled = false
    private(set) var repeatMode = RepeatMode.off
    /// Like Apple Music's Autoplay: when the queue runs out, similar songs follow.
    private(set) var isAutoplayEnabled = false
    /// How many songs at the end of the queue Autoplay added. They wait after everything the
    /// user queued, and Up Next lists them in a section of their own.
    private(set) var autoplayCount = 0
    /// True while Autoplay looks for more songs.
    private(set) var isFindingAutoplayTracks = false
    var isNowPlayingPresented = false

    /// Called the first time each queued track actually starts playing.
    @ObservationIgnored var onTrackStarted: ((Track) -> Void)?
    /// Finds the YouTube video for an album song, which comes from Apple's catalog.
    @ObservationIgnored var matchYouTubeVideo: ((Track) async throws -> Track)?
    /// Finds catalog songs to play after `track` once the queue runs out: similar songs, and
    /// some more by the same artist.
    @ObservationIgnored var findAutoplayTracks: ((Track) async throws -> [Track])?
    @ObservationIgnored let webView: WKWebView

    @ObservationIgnored private let config: AppConfig
    @ObservationIgnored private let coordinator = PlayerWebViewCoordinator()
    @ObservationIgnored private let appleMusic = AppleMusicPlaybackEngine()
    @ObservationIgnored private var isPlayerReady = false
    @ObservationIgnored private var pageLoadFailed = false
    @ObservationIgnored private var pendingVideoID: String?
    /// Where the pending video starts; non-zero only when the player is rebuilt mid-song.
    @ObservationIgnored private var pendingStartTime: TimeInterval = 0
    @ObservationIgnored private var playWatchdog: Task<Void, Never>?
    /// Finding the current album song's YouTube video, before it can load.
    @ObservationIgnored private var matchTask: Task<Void, Never>?
    @ObservationIgnored private var autoplayTask: Task<Void, Never>?
    @ObservationIgnored private var didReportCurrentTrack = false
    /// The queue in its own order while shuffled, so turning shuffle off can put it back.
    @ObservationIgnored private var unshuffledQueue: [Track]?
    /// Where the user last seeked to, until the player confirms it got there.
    @ObservationIgnored private var pendingSeek: (target: TimeInterval, startedAt: Date)?

    init(config: AppConfig) {
        self.config = config
        volume = UserDefaults.standard.object(forKey: StorageKey.playerVolume) as? Double ?? PlaybackPolicy.fullVolume
        isAutoplayEnabled = UserDefaults.standard.bool(forKey: StorageKey.autoplay)
        let configuration = WKWebViewConfiguration()
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        #endif
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(coordinator, name: PlayerBridge.messageHandlerName)
        // Only matters with background play on; in the foreground the page is visible anyway.
        configuration.userContentController.addUserScript(WKUserScript(
            source: PlayerBridge.keepPageVisibleScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: PlayerBridge.systemMediaControlsScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        webView = WKWebView(frame: .zero, configuration: configuration)
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Palette.playerBackground)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #endif
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        #if DEBUG
        webView.isInspectable = true
        #endif

        coordinator.controller = self
        loadPlayerPage()
        #if os(iOS)
        // Music keeps playing with the silent switch on, and in the background when allowed.
        // Cadence never activates this session for YouTube: WebKit plays the video in its own
        // process with its own audio session, and on a real device activating this one interrupts
        // it, pausing the song.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        #endif
        appleMusic.onEvent = { [weak self] event in
            self?.handleAppleMusic(event)
        }
    }

    // MARK: State

    var currentTrack: Track? {
        guard let currentIndex, queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    var isPlaying: Bool { status == .playing || status == .buffering }
    var hasNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex + 1 < queue.count || (repeatMode == .all && supportsShuffleAndRepeat)
    }
    var hasPrevious: Bool { currentIndex != nil }

    private var isAppleMusicQueue: Bool { currentTrack?.source == .appleMusic }

    /// Shuffle and repeat work on YouTube queues; the system Apple Music player keeps its own order.
    var supportsShuffleAndRepeat: Bool { currentTrack != nil && !isAppleMusicQueue }
    /// Up Next can be reordered and trimmed on YouTube queues, for the same reason.
    var canEditQueue: Bool { supportsShuffleAndRepeat }

    /// Experimental and unofficial: keep YouTube playing with Now Playing closed or the app in the
    /// background. Breaks YouTube's API Terms, so it's off unless turned on in Settings.
    private var isYouTubeBackgroundPlayEnabled: Bool {
        UserDefaults.standard.bool(forKey: StorageKey.youtubeBackgroundPlay)
    }

    /// Whether the user wants music playing. Unlike `status`, only the user's own play and pause
    /// change it, so a pause iOS forces on the app can be told apart and undone.
    @ObservationIgnored private var isPlaybackIntended = false
    /// When the app went to the background; nil while it's on screen.
    @ObservationIgnored private var backgroundedAt: Date?
    /// When something that makes WebKit pause video last happened: leaving the screen, or the
    /// player moving into its hidden spot.
    @ObservationIgnored private var systemPauseWindowStart: Date?

    /// Where Autoplay's songs start: after the user's songs, and never before the next song.
    private var autoplayStart: Int {
        guard let currentIndex else { return queue.count }
        return max(currentIndex + 1, queue.count - autoplayCount)
    }

    /// The songs the user queued after this one.
    var upcoming: [QueueItem] {
        guard let currentIndex else { return [] }
        return queueItems(in: (currentIndex + 1)..<autoplayStart, limit: PlaybackPolicy.upNextPreviewLimit)
    }

    /// The songs Autoplay will play once the user's run out.
    var autoplayUpcoming: [QueueItem] {
        guard currentIndex != nil else { return [] }
        return queueItems(in: autoplayStart..<queue.count, limit: PlaybackPolicy.autoplayPreviewLimit)
    }

    private func queueItems(in range: Range<Int>, limit: Int) -> [QueueItem] {
        let end = min(range.upperBound, range.lowerBound + limit)
        guard range.lowerBound < end else { return [] }
        // Copies are counted across the whole queue, so the same song in both sections keeps
        // distinct identities.
        var copiesSeen: [Track.ID: Int] = [:]
        for index in queue.indices where index < range.lowerBound {
            copiesSeen[queue[index].id, default: 0] += 1
        }
        return (range.lowerBound..<end).map { index in
            let track = queue[index]
            let copy = copiesSeen[track.id, default: 0]
            copiesSeen[track.id] = copy + 1
            return QueueItem(id: "\(track.id)#\(copy)", index: index, track: track)
        }
    }

    /// Autoplay songs that have started playing become ordinary history, so the count covers
    /// only those still ahead. Edits call this first, keeping Autoplay's songs at the end.
    private func settleAutoplay() {
        guard let currentIndex else { return }
        autoplayCount = min(autoplayCount, queue.count - (currentIndex + 1))
    }

    // MARK: Queue

    /// Replaces the queue, starts playing and presents Now Playing. A mixed list (like Recents)
    /// is narrowed to songs from the tapped song's service.
    func play(_ tracks: [Track], startingAt index: Int = 0) {
        guard tracks.indices.contains(index) else { return }
        let source = tracks[index].source
        queue = tracks.filter { $0.source == source }
        autoplayCount = 0
        var start = tracks[..<index].filter { $0.source == source }.count
        unshuffledQueue = nil
        if isShuffled && source != .appleMusic {
            // Shuffle carries over, like Apple Music: the chosen song, then the rest in any order.
            unshuffledQueue = queue
            var rest = queue
            let chosen = rest.remove(at: start)
            queue = [chosen] + rest.shuffled()
            start = 0
        }
        isNowPlayingPresented = true
        if source == .appleMusic {
            cancelMatch()
            evaluate(PlayerBridge.pause)
            #if os(iOS)
            // Let the system Apple Music player own audio.
            if #available(iOS 27.0, *) {
                AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in }
            } else {
                // The synchronous call can block, so keep it off the main thread.
                Task.detached {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                }
            }
            #endif
            prepareForTrack(at: start)
            appleMusic.start(queue: queue, at: start)
        } else {
            appleMusic.stop()
            load(index: start)
        }
    }

    func playNext(_ track: Track) {
        guard let currentIndex, currentTrack?.source == track.source else {
            play([track])
            return
        }
        settleAutoplay()
        queue.insert(track, at: currentIndex + 1)
        if isAppleMusicQueue { appleMusic.insertNext(track) }
        // Turning shuffle off keeps it next.
        if let original = unshuffledQueue, let position = indexInUnshuffledQueue(of: queue[currentIndex]) {
            unshuffledQueue?.insert(track, at: min(position + 1, original.count))
        }
    }

    /// Adds `track` after everything queued and before Autoplay's songs, or plays it when
    /// nothing from its service is.
    func playLast(_ track: Track) {
        guard currentIndex != nil, currentTrack?.source == track.source else {
            play([track])
            return
        }
        settleAutoplay()
        let position = queue.count - autoplayCount
        queue.insert(track, at: position)
        if let original = unshuffledQueue {
            unshuffledQueue?.insert(track, at: original.count - autoplayCount)
        }
        if isAppleMusicQueue { appleMusic.insert(track, at: position) }
    }

    /// Reorders the user's songs in Up Next. Offsets count from the song after this one, as
    /// `upcoming` lists them.
    func moveUpNext(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard canEditQueue, let currentIndex else { return }
        settleAutoplay()
        let first = currentIndex + 1
        queue.move(fromOffsets: IndexSet(offsets.map { $0 + first }), toOffset: destination + first)
    }

    /// Takes songs out of Up Next. Offsets count from the song after this one.
    func removeUpNext(atOffsets offsets: IndexSet) {
        guard canEditQueue, let currentIndex else { return }
        settleAutoplay()
        for index in offsets.map({ $0 + currentIndex + 1 }).sorted(by: >) where queue.indices.contains(index) {
            if index >= autoplayStart { autoplayCount -= 1 }
            let removed = queue.remove(at: index)
            if let position = indexInUnshuffledQueue(of: removed) {
                unshuffledQueue?.remove(at: position)
            }
        }
    }

    /// Moves a queued song up to play right after this one. An Autoplay song becomes one of the
    /// user's.
    func playNext(queuedAt index: Int) {
        guard canEditQueue, let currentIndex, index > currentIndex else { return }
        settleAutoplay()
        if index >= autoplayStart { autoplayCount -= 1 }
        queue.move(fromOffsets: [index], toOffset: currentIndex + 1)
    }

    /// Empties the user's part of Up Next; the current song plays on, and Autoplay after it.
    func clearUpNext() {
        guard canEditQueue, let currentIndex else { return }
        settleAutoplay()
        let cleared = queue[(currentIndex + 1)..<autoplayStart]
        queue.removeSubrange((currentIndex + 1)..<autoplayStart)
        for track in cleared {
            if let position = indexInUnshuffledQueue(of: track) {
                unshuffledQueue?.remove(at: position)
            }
        }
    }

    /// Shuffles the songs after this one, or puts them back in order, carrying on with this song.
    func toggleShuffle() {
        guard supportsShuffleAndRepeat, let currentIndex else { return }
        let current = queue[currentIndex]
        if let original = unshuffledQueue {
            unshuffledQueue = nil
            isShuffled = false
            guard let position = indexInUnshuffledQueue(of: current) else { return }
            queue = original
            // The song may have found its YouTube video since the order was saved.
            queue[position] = current
            self.currentIndex = position
        } else {
            settleAutoplay()
            unshuffledQueue = queue
            isShuffled = true
            // Autoplay's songs stay after the user's, in their own order, like Apple Music.
            queue = Array(queue[...currentIndex]) + queue[(currentIndex + 1)..<autoplayStart].shuffled()
                + queue[autoplayStart...]
        }
    }

    func toggleAutoplay() {
        isAutoplayEnabled.toggle()
        UserDefaults.standard.set(isAutoplayEnabled, forKey: StorageKey.autoplay)
        if isAutoplayEnabled {
            extendQueueForAutoplayIfNeeded()
        } else {
            removeAutoplayTracks()
        }
    }

    /// Keeps a few Autoplay songs waiting after the user's, so Up Next shows what plays once
    /// they run out, and tops them up as they're played. Repeating the queue already keeps it going.
    private func extendQueueForAutoplayIfNeeded() {
        guard isAutoplayEnabled, repeatMode == .off, autoplayTask == nil,
              currentIndex != nil, let seed = queue.last, let findAutoplayTracks
        else { return }
        settleAutoplay()
        guard autoplayCount < PlaybackPolicy.autoplayRefillThreshold else { return }
        isFindingAutoplayTracks = true
        autoplayTask = Task {
            defer {
                autoplayTask = nil
                isFindingAutoplayTracks = false
            }
            guard let found = try? await findAutoplayTracks(seed) else { return }
            appendAutoplayTracks(found, after: seed)
        }
    }

    /// Turning Autoplay off takes out the songs it added that haven't played yet.
    private func removeAutoplayTracks() {
        autoplayTask?.cancel()
        autoplayTask = nil
        isFindingAutoplayTracks = false
        settleAutoplay()
        guard autoplayCount > 0 else { return }
        if isAppleMusicQueue {
            // The system player's queue can't drop songs, so they play on; they're simply no
            // longer marked as Autoplay's.
            autoplayCount = 0
            return
        }
        queue.removeLast(autoplayCount)
        if let original = unshuffledQueue {
            unshuffledQueue = Array(original.dropLast(autoplayCount))
        }
        autoplayCount = 0
    }

    private func appendAutoplayTracks(_ candidates: [Track], after seed: Track) {
        // Something else was queued meanwhile, so the queue no longer ends here.
        guard queue.last == seed else { return }
        let queuedIDs = Set(queue.compactMap(\.catalogSongID))
        let queuedSongs = Set(queue.map(Self.songKey))
        let fresh = candidates
            .filter { !queuedIDs.contains($0.id) && !queuedSongs.contains(Self.songKey($0)) }
            .prefix(PlaybackPolicy.autoplayBatchSize)
        guard !fresh.isEmpty else { return }
        // Apple Music songs play as they are in an Apple Music queue; anywhere else through YouTube.
        let playable = isAppleMusicQueue ? Array(fresh) : fresh.map(\.forYouTubePlayback)
        settleAutoplay()
        queue += playable
        unshuffledQueue? += playable
        autoplayCount += playable.count
        if isAppleMusicQueue { playable.forEach(appleMusic.append) }
    }

    /// The song's name without "(feat. X)" or "(Official Video)", to spot one already queued,
    /// whether it's a catalog song or a YouTube video.
    private static func songKey(_ track: Track) -> String {
        let title = track.catalogSongID == nil ? SongQuery(track: track).title : track.title
        return SongTitle.removingBracketedText(from: title).trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Off, then the whole queue, then just this song, like Apple Music.
    func cycleRepeatMode() {
        guard supportsShuffleAndRepeat else { return }
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        // Back to playing through once: Autoplay can carry on from the end again.
        if repeatMode == .off { extendQueueForAutoplayIfNeeded() }
    }

    /// Where `track` sits in the unshuffled order; an album song counts once it has its video.
    private func indexInUnshuffledQueue(of track: Track) -> Int? {
        unshuffledQueue?.firstIndex { candidate in
            candidate.id == track.id || (candidate.catalogSongID != nil && candidate.catalogSongID == track.catalogSongID)
        }
    }

    func jump(to index: Int) {
        guard queue.indices.contains(index) else { return }
        if isAppleMusicQueue {
            prepareForTrack(at: index)
            appleMusic.start(queue: queue, at: index)
        } else {
            load(index: index)
        }
    }

    func next() {
        guard let currentIndex, hasNext else { return }
        if isAppleMusicQueue {
            appleMusic.skipToNext()
        } else {
            // Past the last song only when repeating the queue.
            load(index: currentIndex + 1 < queue.count ? currentIndex + 1 : 0)
        }
    }

    func previous() {
        guard let currentIndex else { return }
        if isAppleMusicQueue {
            appleMusic.skipToPrevious()
        } else if currentTime > PlaybackPolicy.restartThreshold || currentIndex == 0 {
            seek(to: 0)
        } else {
            load(index: currentIndex - 1)
        }
    }

    // MARK: Transport

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    /// Resumes, replays or retries the current track. YouTube presents Now Playing first.
    func resume() {
        guard let currentIndex else { return }
        if isAppleMusicQueue {
            switch status {
            case .ended, .failed, .idle:
                appleMusic.start(queue: queue, at: currentIndex)
            default:
                appleMusic.play()
            }
            return
        }
        if !isYouTubeBackgroundPlayEnabled {
            isNowPlayingPresented = true
        }
        isPlaybackIntended = true
        switch status {
        case .ended, .failed, .idle:
            load(index: currentIndex)
        default:
            requestPlay()
        }
    }

    func pause() {
        isPlaybackIntended = false
        if isAppleMusicQueue {
            appleMusic.pause()
            return
        }
        switch status {
        case .playing, .buffering, .loading:
            evaluate(PlayerBridge.pause)
        default:
            break
        }
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        pendingSeek = (time, .now)
        if isAppleMusicQueue {
            appleMusic.seek(to: time)
        } else {
            evaluate(PlayerBridge.seek(to: time))
        }
    }

    func presentNowPlaying() {
        guard currentTrack != nil else { return }
        isNowPlayingPresented = true
    }

    /// The embedded YouTube player may not play while hidden unless background play is on;
    /// other services keep playing.
    func handleNowPlayingDismissed() {
        guard currentTrack?.requiresVisiblePlayer == true, !isYouTubeBackgroundPlayEnabled else { return }
        pause()
    }

    /// Background play shows artwork instead of the video, so the video stops rendering.
    /// Turning it off brings back YouTube's rule: no playback while the player is hidden.
    func backgroundPlaySettingChanged() {
        applyVideoVisibility()
        if !isYouTubeBackgroundPlayEnabled && !isNowPlayingPresented {
            handleNowPlayingDismissed()
        }
    }

    private func applyVideoVisibility() {
        evaluate(PlayerBridge.setVideoHidden(isYouTubeBackgroundPlayEnabled))
    }

    func setVolume(_ newVolume: Double) {
        volume = newVolume
        UserDefaults.standard.set(newVolume, forKey: StorageKey.playerVolume)
        evaluate(PlayerBridge.setVolume(newVolume))
    }

    /// A fresh player page starts at full volume with the video showing.
    private func configureNewPlayer() {
        isPlayerReady = true
        applyVideoVisibility()
        evaluate(PlayerBridge.setVolume(volume))
    }

    func handleAppDidEnterBackground() {
        backgroundedAt = .now
        systemPauseWindowStart = .now
        guard currentTrack?.requiresVisiblePlayer == true else { return }
        guard isYouTubeBackgroundPlayEnabled else {
            pause()
            return
        }
        // iOS may already have paused the video before the app was reported as backgrounded.
        if isPlaybackIntended && !isPlaying {
            resumeAfterSystemPause()
        }
    }

    /// The player moved into its hidden spot, which happens when background play is turned on.
    /// WebKit pauses video that briefly leaves the screen, so treat a pause right after this as
    /// WebKit's, not the user's.
    func webViewDidMove() {
        guard isYouTubeBackgroundPlayEnabled, currentTrack?.requiresVisiblePlayer == true else { return }
        systemPauseWindowStart = .now
        if isPlaybackIntended && status == .paused {
            resumeAfterSystemPause()
        }
    }

    func handleAppDidBecomeActive() {
        backgroundedAt = nil
        // Pauses from Control Center while the app was on screen count as the user's.
        if currentTrack?.requiresVisiblePlayer == true {
            isPlaybackIntended = isPlaying || status == .loading
        }
    }

    /// A pause this soon after leaving the screen or moving the player comes from WebKit, not the user.
    private var isInSystemPauseWindow: Bool {
        guard let systemPauseWindowStart else { return false }
        return Date.now.timeIntervalSince(systemPauseWindowStart) < PlaybackPolicy.backgroundPauseWindow
    }

    /// WebKit pauses web video when it leaves the screen. With background play on, start it again,
    /// retrying briefly in case the first attempt lands before WebKit has finished pausing.
    /// The background task keeps the app awake until WebKit's playback takes over.
    private func resumeAfterSystemPause() {
        let backgroundTask = AppActivity.beginBackgroundTask()
        Task {
            for attempt in 0..<PlaybackPolicy.backgroundResumeAttempts {
                // The first try goes out at once to keep the silence short.
                if attempt > 0 {
                    try? await Task.sleep(for: PlaybackPolicy.backgroundResumeDelay)
                }
                guard isPlaybackIntended, !isPlaying else { break }
                evaluate(PlayerBridge.play)
            }
            AppActivity.endBackgroundTask(backgroundTask)
        }
    }

    /// Plays, and with background play on, rebuilds the player if WebKit ignores the request.
    private func requestPlay() {
        evaluate(PlayerBridge.play)
        guard isYouTubeBackgroundPlayEnabled else { return }
        playWatchdog?.cancel()
        playWatchdog = Task {
            try? await Task.sleep(for: PlaybackPolicy.playStartTimeout)
            guard !Task.isCancelled else { return }
            rebuildPlayerIfStalled()
        }
    }

    /// Background play can leave WebKit believing iOS still has the video paused. It then ignores
    /// the app's requests to play, though the system's own controls still work. A fresh player
    /// page starts clean, and the song carries on from the same moment.
    private func rebuildPlayerIfStalled() {
        guard isPlaybackIntended, status == .paused, AppActivity.isActive,
              let currentTrack, currentTrack.requiresVisiblePlayer,
              PlayerBridge.isValidVideoID(currentTrack.id) else { return }
        pendingVideoID = currentTrack.id
        pendingStartTime = currentTime
        status = .loading
        loadPlayerPage()
    }

    // MARK: Apple Music

    private func prepareForTrack(at index: Int) {
        currentIndex = index
        currentTime = 0
        pendingSeek = nil
        duration = queue[index].duration ?? 0
        didReportCurrentTrack = false
    }

    private func handleAppleMusic(_ event: AppleMusicPlaybackEngine.Event) {
        switch event {
        case .status(let newStatus):
            status = newStatus
            if newStatus == .playing { reportTrackStartIfNeeded() }
        case .progress(let current, let total):
            applyReportedPosition(current, duration: total)
        case .currentIndex(let index):
            guard index != currentIndex, queue.indices.contains(index) else { return }
            prepareForTrack(at: index)
            if status == .playing { reportTrackStartIfNeeded() }
        }
    }

    /// Players keep reporting the old position for a moment after a seek; accepting those would
    /// snap the scrubber and lyrics back before they jump forward. Reports are ignored until the
    /// player reaches the seek target, or a short timeout passes.
    private func applyReportedPosition(_ position: TimeInterval, duration total: TimeInterval) {
        if total.isFinite && total > 0 { duration = total }
        guard position.isFinite, position >= 0 else { return }
        if let pendingSeek {
            let hasCaughtUp = abs(position - pendingSeek.target) <= PlaybackPolicy.seekTolerance
            let hasTimedOut = Date.now.timeIntervalSince(pendingSeek.startedAt) > PlaybackPolicy.seekSettleTimeout
            guard hasCaughtUp || hasTimedOut else { return }
            self.pendingSeek = nil
        }
        currentTime = position
    }

    private func reportTrackStartIfNeeded() {
        guard !didReportCurrentTrack, let currentTrack else { return }
        didReportCurrentTrack = true
        onTrackStarted?(currentTrack)
        extendQueueForAutoplayIfNeeded()
    }

    // MARK: Loading

    private func load(index: Int) {
        prepareForTrack(at: index)
        cancelMatch()

        let track = queue[index]
        if track.needsYouTubeMatch {
            status = .loading
            isPlaybackIntended = true
            pendingVideoID = nil
            matchTask = Task { await loadMatch(for: track, at: index) }
            return
        }
        let videoID = track.id
        guard PlayerBridge.isValidVideoID(videoID) else {
            status = .failed(.playback(.invalidVideo))
            return
        }
        status = .loading
        isPlaybackIntended = true
        if isPlayerReady {
            evaluate(PlayerBridge.load(videoID: videoID, autoplay: isNowPlayingPresented || isYouTubeBackgroundPlayEnabled))
        } else {
            pendingVideoID = videoID
            pendingStartTime = 0
            if pageLoadFailed { loadPlayerPage() }
        }
    }

    /// Album songs come from Apple's catalog, so their YouTube video is found first. The match
    /// takes the song's place in the queue, so it's only looked up once.
    private func loadMatch(for track: Track, at index: Int) async {
        // Keeps the app awake between album songs while it plays in the background.
        let backgroundTask = AppActivity.beginBackgroundTask()
        defer { AppActivity.endBackgroundTask(backgroundTask) }
        let match: Track
        do {
            guard let matchYouTubeVideo else { throw AppError.playback(.noYouTubeMatch) }
            match = try await matchYouTubeVideo(track)
        } catch {
            // A cancelled search means another song took over.
            guard !Task.isCancelled else { return }
            matchTask = nil
            status = .failed(AppError(error))
            return
        }
        guard !Task.isCancelled else { return }
        matchTask = nil
        guard currentIndex == index, queue.indices.contains(index), queue[index] == track else { return }
        queue[index] = match
        load(index: index)
    }

    private func cancelMatch() {
        matchTask?.cancel()
        matchTask = nil
    }

    /// While the next song's video is being found, the previous video's events are stale.
    private var isFindingVideo: Bool { matchTask != nil }

    private func loadPlayerPage() {
        isPlayerReady = false
        pageLoadFailed = false
        webView.loadHTMLString(PlayerBridge.html(origin: config.playerOrigin), baseURL: config.playerOrigin)
    }

    private func evaluate(_ script: String) {
        guard isPlayerReady else { return }
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: Player events

    fileprivate func handleMessage(_ body: Any) {
        guard let message = PlayerBridge.Message(body: body) else { return }
        // While Apple Music plays, the idle YouTube player's events must not touch shared state.
        if isAppleMusicQueue {
            if case .ready = message {
                configureNewPlayer()
            }
            return
        }
        switch message {
        case .ready:
            configureNewPlayer()
            if let pendingVideoID {
                self.pendingVideoID = nil
                evaluate(PlayerBridge.load(
                    videoID: pendingVideoID,
                    autoplay: isNowPlayingPresented || isYouTubeBackgroundPlayEnabled,
                    startingAt: pendingStartTime
                ))
                pendingStartTime = 0
            }
        case .stateChange(let state):
            guard !isFindingVideo else { return }
            handle(state)
        case .progress(let current, let total):
            guard !isFindingVideo else { return }
            applyReportedPosition(current, duration: total)
        case .error(let code):
            guard !isFindingVideo else { return }
            status = .failed(.playback(PlaybackFailure(youtubeErrorCode: code)))
        case .apiLoadFailed:
            markPageFailed(with: .offline)
        case .previousTrack:
            previous()
        case .nextTrack:
            next()
        }
    }

    fileprivate func handlePageFailure() {
        markPageFailed(with: .playback(.playerStopped))
    }

    private func markPageFailed(with error: AppError) {
        isPlayerReady = false
        pageLoadFailed = true
        if currentIndex != nil {
            pendingVideoID = nil
            status = .failed(error)
        }
    }

    private func handle(_ state: PlayerBridge.State) {
        switch state {
        case .unstarted:
            break
        case .buffering:
            status = .buffering
        case .playing:
            guard isNowPlayingPresented || isYouTubeBackgroundPlayEnabled else {
                // Policy: never keep playing while the player is hidden.
                evaluate(PlayerBridge.pause)
                return
            }
            isPlaybackIntended = true
            status = .playing
            reportTrackStartIfNeeded()
        case .paused, .cued:
            status = .paused
            guard isYouTubeBackgroundPlayEnabled else { break }
            if isPlaybackIntended && isInSystemPauseWindow {
                resumeAfterSystemPause()
            } else if backgroundedAt != nil {
                // Paused later from the Lock Screen or Control Center: respect it.
                isPlaybackIntended = false
            }
        case .ended:
            status = .ended
            if repeatMode == .one, let currentIndex {
                load(index: currentIndex)
            } else if hasNext {
                next()
            }
        }
    }
}

/// Bridges WebKit callbacks without the user content controller retaining `PlayerController`.
private final class PlayerWebViewCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    weak var controller: PlayerController?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        controller?.handleMessage(message.body)
    }

    /// Keeps the player page in place; links inside the player (e.g. the YouTube logo) open in YouTube.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame == true,
              navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url
        else { return .allow }
        await AppActivity.open(url)
        return .cancel
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            Task { await AppActivity.open(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        controller?.handlePageFailure()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        controller?.handlePageFailure()
    }
}

/// The app-level calls the player needs, which differ between UIKit and AppKit.
private enum AppActivity {
    #if os(iOS)
    typealias BackgroundTask = UIBackgroundTaskIdentifier

    static var isActive: Bool { UIApplication.shared.applicationState == .active }

    static func beginBackgroundTask() -> BackgroundTask { UIApplication.shared.beginBackgroundTask() }

    static func endBackgroundTask(_ task: BackgroundTask) { UIApplication.shared.endBackgroundTask(task) }

    static func open(_ url: URL) async { await UIApplication.shared.open(url) }
    #else
    /// Mac apps keep running in the background, so there's nothing to hold open.
    struct BackgroundTask {}

    static var isActive: Bool { NSApplication.shared.isActive }

    static func beginBackgroundTask() -> BackgroundTask { BackgroundTask() }

    static func endBackgroundTask(_ task: BackgroundTask) {}

    static func open(_ url: URL) async { NSWorkspace.shared.open(url) }
    #endif
}
