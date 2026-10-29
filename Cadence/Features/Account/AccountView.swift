import SwiftUI

struct AccountView: View {
    @Environment(GoogleAuthService.self) private var auth
    @Environment(YouTubeAPIClient.self) private var api
    @Environment(LibraryStore.self) private var library
    @Environment(ServiceHub.self) private var hub
    #if os(iOS)
    @Environment(AppleMusicCatalog.self) private var appleMusic
    #endif
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding = true
    @AppStorage(StorageKey.wordByWordLyrics) private var isWordSweepEnabled = false
    @AppStorage(StorageKey.youtubeBackgroundPlay) private var isYouTubeBackgroundPlayEnabled = false
    @State private var profile: LoadState<ChannelProfile?> = .idle
    @State private var isConfirmingDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                serviceSection
                switch hub.current {
                case .youtube, .spotify: accountSection
                case .appleMusic:
                    #if os(iOS)
                    appleMusicSection
                    #else
                    accountSection
                    #endif
                }
                experimentalSection
                if hub.current == .youtube {
                    configurationSection
                }
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationTitleStyle(.inline)
            #if os(iOS)
            // On the Mac, Settings is its own window with a close button.
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { appleMusic.refreshAuthorization() }
            #endif
            .task(id: auth.isSignedIn) { await loadProfile() }
            .confirmationDialog(
                "Disconnect your YouTube account?",
                isPresented: $isConfirmingDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    Task {
                        await auth.signOut()
                        library.reset()
                    }
                }
            } message: {
                Text("Your playlists stay on YouTube. Recently played history on this device is kept.")
            }
        }
    }

    private var serviceSection: some View {
        Section {
            ForEach(MusicService.allCases) { service in
                Button {
                    hub.select(service)
                } label: {
                    ServiceOptionRow(service: service, isSelected: hub.current == service)
                }
                .buttonStyle(.plain)
                .disabled(!service.isAvailable)
            }
        } header: {
            Text("Music Service")
        } footer: {
            Text("Home, Discover, Playlists, Search and Recently Played show only the selected service's music.")
        }
    }

    #if os(iOS)
    private var appleMusicSection: some View {
        Section {
            if appleMusic.isConnected {
                Label("Library Access Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
            } else {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text(appleMusic.connectPrompt)
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                    ConnectAccountButton(showsSetupHint: false)
                }
                .padding(.vertical, Spacing.small)
            }
        } header: {
            Text("Apple Music")
        } footer: {
            Text("Playing songs needs an Apple Music subscription on this iPhone. Apple Music can't play in the Simulator.")
        }
    }
    #endif

    private var accountSection: some View {
        Section {
            if auth.isSignedIn {
                profileRow
                Button("Disconnect Account", role: .destructive) { isConfirmingDisconnect = true }
            } else {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text("Connect to play your YouTube playlists, create new ones and add songs.")
                        .font(Typography.footnote)
                        .foregroundStyle(Palette.textSecondary)
                    ConnectAccountButton(showsSetupHint: false)
                    if !auth.isConfigured {
                        Label("Add GOOGLE_CLIENT_ID to Config/Secrets.xcconfig to enable this.", systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
                .padding(.vertical, Spacing.small)
            }
        } header: {
            Text("YouTube Account")
        }
    }

    @ViewBuilder private var profileRow: some View {
        switch profile {
        case .idle, .loading:
            HStack(spacing: Spacing.medium) {
                ProgressView()
                Text("Loading account…")
                    .foregroundStyle(Palette.textSecondary)
            }
        case .loaded(let channel):
            HStack(spacing: Spacing.medium) {
                ArtworkView(url: channel?.avatarURL, size: ArtworkSize.row, placeholderSymbol: "person.fill")
                    .clipShape(.circle)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(channel?.title ?? String(localized: "YouTube Account"))
                        .font(Typography.rowTitle)
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.success)
                }
            }
            .accessibilityElement(children: .combine)
        case .failed(let error):
            Label {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(error.title)
                    Text(error.message)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            } icon: {
                Image(systemName: error.systemImage)
                    .foregroundStyle(Palette.warning)
            }
        }
    }

    /// One section per toggle, so each explanation sits right under the toggle it belongs to.
    @ViewBuilder private var experimentalSection: some View {
        Section {
            Toggle(isOn: $isWordSweepEnabled) {
                Label("Word-by-Word Lyrics", systemImage: "text.word.spacing")
            }
        } header: {
            Text("Experimental")
        } footer: {
            Text("Lights up synced lyrics word by word. LRCLIB only times whole lines, so the pace within a line is estimated.")
        }
        Section {
            Toggle(isOn: $isYouTubeBackgroundPlayEnabled) {
                Label("YouTube Background Play", systemImage: "lock.iphone")
            }
        } footer: {
            Text("Unofficial and for personal use only: keeps YouTube playing with the player closed or the phone locked. That breaks YouTube's API Terms and could get your Google Cloud project suspended.")
        }
    }

    private var configurationSection: some View {
        Section {
            LabeledContent("YouTube API key") {
                ConfigurationStatus(isConfigured: api.hasAPIKey)
            }
            LabeledContent("Google client ID") {
                ConfigurationStatus(isConfigured: auth.isConfigured)
            }
            LabeledContent("Charts region", value: api.regionName)
        } header: {
            Text("Configuration")
        } footer: {
            Text("Set these in Config/Secrets.xcconfig. Browsing works with an API key or a connected account.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Link(destination: LegalLink.youtubeTerms) {
                Label("YouTube Terms of Service", systemImage: "doc.text")
            }
            Link(destination: LegalLink.googlePrivacy) {
                Label("Google Privacy Policy", systemImage: "hand.raised")
            }
            Link(destination: LegalLink.manageAccess) {
                Label("Manage Google Account Access", systemImage: "key")
            }
            Link(destination: LyricsEndpoint.homepage) {
                Label("Lyrics by LRCLIB", systemImage: "quote.bubble")
            }
            Button("Show Onboarding Again", systemImage: "sparkles") {
                dismiss()
                hasCompletedOnboarding = false
            }
        }
    }

    private func loadProfile() async {
        guard auth.isSignedIn else {
            profile = .idle
            return
        }
        await refreshContent($profile) { try await api.myChannel() }
    }
}

private struct ConfigurationStatus: View {
    let isConfigured: Bool

    var body: some View {
        // A Label here makes LabeledContent rows grow very tall, so lay it out by hand.
        HStack(spacing: Spacing.xSmall) {
            Image(systemName: isConfigured ? "checkmark.circle.fill" : "xmark.circle.fill")
                .accessibilityHidden(true)
            Text(isConfigured ? "Configured" : "Missing")
        }
        .foregroundStyle(isConfigured ? Palette.success : Palette.warning)
    }
}

#Preview {
    AccountView()
        .appEnvironment(.preview())
}
