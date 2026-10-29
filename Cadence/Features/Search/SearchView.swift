import SwiftUI

struct SearchView: View {
    @Environment(ServiceHub.self) private var hub
    @Environment(AppRouter.self) private var router
    @Environment(PlayerController.self) private var player
    @State private var query = ""
    @State private var results: LoadState<[Track]> = .idle
    /// The query and service the results on screen belong to.
    @State private var resultsQuery = ""
    @State private var resultsService: MusicService?
    /// Earlier results, so going back to a query (or pressing Search after the live search) is free.
    @State private var cache: [SearchKey: [Track]] = [:]
    @State private var isSearching = false
    /// Bumped by the Search key, which searches at once instead of after the typing pause.
    @State private var submitCount = 0
    @State private var handledSubmitCount = 0

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack(path: router.path(for: .search)) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { Palette.backgroundGradient.ignoresSafeArea() }
                .navigationTitle("Search")
                .catalogPageDestinations()
                .toolbar {
                    // Earlier results stay on screen while the next ones load.
                    ToolbarItem(placement: .primaryAction) {
                        if isSearching && results.value != nil {
                            ProgressView()
                        }
                    }
                }
                .searchable(text: $query, prompt: Text("Songs, artists, music videos"))
                .onSubmit(of: .search) { submitCount += 1 }
                // Results follow the typing. YouTube search costs 100 quota units per request, so
                // it waits for a pause and a couple of characters, and earlier results are reused.
                .task(id: SearchRequest(query: trimmedQuery, service: hub.current, submitCount: submitCount)) {
                    let isSubmit = submitCount != handledSubmitCount
                    handledSubmitCount = submitCount
                    await search(trimmedQuery, waitsForPause: !isSubmit)
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch results {
        case .idle:
            EmptyStateView(
                title: LocalizedStringKey(String(localized: "Search \(hub.current.name)")),
                systemImage: "magnifyingglass",
                message: "Find songs and artists. Results appear as you type."
            )
        case .loading:
            LoadingStateView("Searching…")
        case .failed(let error):
            ErrorStateView(error: error) {
                Task { await search(trimmedQuery, waitsForPause: false) }
            }
        case .loaded(let tracks) where tracks.isEmpty:
            ContentUnavailableView.search(text: resultsQuery)
        case .loaded(let tracks):
            TrackCollection(tracks, id: { index, _ in index }) { _, track in
                SongRow(for: track) {
                    // Results aren't a list to play through, so only the chosen song plays and
                    // nothing queues after it; Autoplay carries on from it when it's on.
                    player.play([track])
                } label: {
                    TrackRow(track: track, isCurrent: player.currentTrack?.id == track.id)
                }
            }
        }
    }

    /// Typing cancels the previous call (the task restarts), so only the query typed last loads.
    private func search(_ text: String, waitsForPause: Bool) async {
        // Another service's results never stay on screen, even briefly.
        if resultsService != hub.current {
            results = .idle
            resultsQuery = ""
        }
        guard text.count >= SearchPolicy.minimumQueryLength else {
            if text.isEmpty {
                results = .idle
                resultsQuery = ""
            }
            return
        }
        let key = SearchKey(query: text.lowercased(), service: hub.current)
        if let cached = cache[key] {
            show(cached, for: text)
            return
        }
        if waitsForPause {
            do {
                try await Task.sleep(for: SearchPolicy.typingPause)
            } catch {
                return
            }
        }
        isSearching = true
        defer { isSearching = false }
        let error = await refreshContent($results) { try await hub.catalog.search(text) }
        guard !Task.isCancelled else { return }
        if let error {
            // The results still on screen belong to an earlier query, so show what went wrong.
            results = .failed(error)
        } else if let tracks = results.value {
            cache[key] = tracks
            resultsQuery = text
            resultsService = key.service
        }
    }

    private func show(_ tracks: [Track], for text: String) {
        results = .loaded(tracks)
        resultsQuery = text
        resultsService = hub.current
    }
}

private struct SearchKey: Hashable {
    let query: String
    let service: MusicService
}

private struct SearchRequest: Equatable {
    let query: String
    let service: MusicService
    let submitCount: Int
}

#Preview {
    SearchView()
        .appEnvironment(.preview())
}
