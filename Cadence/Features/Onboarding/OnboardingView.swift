import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @Environment(ServiceHub.self) private var hub
    @State private var step: OnboardingStep = .welcome

    var body: some View {
        VStack(spacing: Spacing.large) {
            topBar
                .padding(.horizontal, Spacing.xLarge)
            ScrollView {
                OnboardingStepContent(
                    step: step,
                    service: hub.current,
                    isConnected: hub.catalog.isConnected,
                    isConfigured: hub.catalog.isConfigured
                )
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            // Margins inside the scroll view leave room for the glass shadows instead of clipping them.
            .contentMargins(Spacing.xLarge, for: .scrollContent)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .defaultScrollAnchor(.center, for: .alignment)
            actions
                .padding(.horizontal, Spacing.xLarge)
        }
        .padding(.vertical, Spacing.large)
        .frame(maxWidth: Layout.readableContentWidth)
        .frame(maxWidth: .infinity)
        .background { Palette.backgroundGradient.ignoresSafeArea() }
        .animation(Motion.standard, value: step)
    }

    private var topBar: some View {
        HStack {
            Button("Back", systemImage: "chevron.left") {
                if let previous = step.previous { step = previous }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .opacity(step.previous == nil ? Opacity.hidden : Opacity.opaque)
            .disabled(step.previous == nil)

            Spacer()
            StepIndicator(currentIndex: step.rawValue, count: OnboardingStep.allCases.count)
            Spacer()

            Button("Skip", action: onFinish)
                .buttonStyle(.glass)
                .opacity(step.next == nil ? Opacity.hidden : Opacity.opaque)
                .disabled(step.next == nil)
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: Spacing.medium) {
            if let next = step.next {
                Button {
                    step = next
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            } else if hub.catalog.isConnected {
                Button(action: onFinish) {
                    Text("Get Started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            } else {
                // The step content already explains a missing client ID.
                ConnectAccountButton(showsSetupHint: false)
                Button(action: onFinish) {
                    Text("Not Now").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
        }
        .controlSize(.large)
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case service
    case playback
    case account

    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }

    func systemImage(for service: MusicService) -> String {
        switch self {
        case .welcome: "music.note.house.fill"
        case .service: "square.stack.3d.up.fill"
        case .playback: service == .youtube ? "play.rectangle.fill" : "play.circle.fill"
        case .account: service == .youtube ? "person.crop.circle.badge.plus" : "music.note.list"
        }
    }

    func title(for service: MusicService) -> LocalizedStringKey {
        switch self {
        case .welcome: "Welcome to Cadence"
        case .service: "Choose Your Music"
        case .playback: "How Playback Works"
        case .account: service == .youtube ? "Connect Your Account" : "Your Apple Music Library"
        }
    }

    func message(for service: MusicService) -> LocalizedStringKey {
        switch (self, service) {
        case (.welcome, _): "One native home for your music."
        case (.service, _): "Pick where your music comes from. You can switch any time in Settings."
        case (.playback, .youtube): "Cadence uses YouTube's official player, so a few of YouTube's rules apply."
        case (.playback, _): "Songs play through Apple Music, just like in the Music app."
        case (.account, .youtube): "Cadence asks Google for permission to manage your YouTube playlists. Nothing else is needed."
        case (.account, _): "Cadence asks for access to your Apple Music library to show your playlists and recently added songs."
        }
    }

    func highlights(for service: MusicService) -> [OnboardingHighlight] {
        switch (self, service) {
        case (.welcome, _):
            [
                OnboardingHighlight(systemImage: "square.grid.2x2", text: "Trending music and every genre to discover"),
                OnboardingHighlight(systemImage: "magnifyingglass", text: "Search songs and artists"),
                OnboardingHighlight(systemImage: "quote.bubble", text: "Synced lyrics for most songs"),
            ]
        case (.service, _):
            []
        case (.playback, .youtube):
            [
                OnboardingHighlight(systemImage: "play.rectangle", text: "Songs play in YouTube's own player"),
                OnboardingHighlight(systemImage: "eye", text: "The video stays on screen while it plays"),
                OnboardingHighlight(systemImage: "pause.circle", text: "Closing the player or leaving the app pauses playback"),
            ]
        case (.playback, _):
            [
                OnboardingHighlight(systemImage: "lock.iphone", text: "Keeps playing in the background and on the Lock Screen"),
                OnboardingHighlight(systemImage: "person.crop.circle.badge.checkmark", text: "Needs an Apple Music subscription"),
                OnboardingHighlight(systemImage: "iphone", text: "Plays on iPhone, not in the Simulator"),
            ]
        case (.account, .youtube):
            [
                OnboardingHighlight(systemImage: "music.note.list", text: "See and play your YouTube playlists"),
                OnboardingHighlight(systemImage: "plus.circle", text: "Create playlists and add songs"),
                OnboardingHighlight(systemImage: "lock.shield", text: "Disconnect any time from Settings"),
            ]
        case (.account, _):
            [
                OnboardingHighlight(systemImage: "music.note.list", text: "See and play your library playlists"),
                OnboardingHighlight(systemImage: "clock.badge.checkmark", text: "Recently added songs on Home"),
                OnboardingHighlight(systemImage: "gearshape", text: "Change access any time in the Settings app"),
            ]
        }
    }
}

struct OnboardingHighlight: Identifiable {
    let systemImage: String
    let text: LocalizedStringKey

    var id: String { systemImage }
}

private struct OnboardingStepContent: View {
    let step: OnboardingStep
    let service: MusicService
    let isConnected: Bool
    let isConfigured: Bool

    @Environment(ServiceHub.self) private var hub

    private var isAccountConnected: Bool { step == .account && isConnected }

    var body: some View {
        VStack(spacing: Spacing.xLarge) {
            Image(systemName: isAccountConnected ? "checkmark.circle.fill" : step.systemImage(for: service))
                .font(Typography.heroSymbol)
                .foregroundStyle(isAccountConnected ? Palette.success : Palette.brand)
                .symbolEffect(.bounce, value: isAccountConnected)
                .frame(width: IconSize.hero, height: IconSize.hero)
                .padding(Spacing.large)
                .glassEffect(.regular.tint(Palette.brand.opacity(Opacity.tint)), in: .circle)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.small) {
                Text(isAccountConnected ? "You're Connected" : step.title(for: service))
                    .font(Typography.display)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(step.message(for: service))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if step == .service {
                VStack(spacing: Spacing.medium) {
                    ForEach(MusicService.allCases) { option in
                        Button {
                            hub.select(option)
                        } label: {
                            ServiceOptionRow(service: option, isSelected: option == service)
                                .padding(Spacing.large)
                                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.large))
                        }
                        .buttonStyle(.plain)
                        .disabled(!option.isAvailable)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    ForEach(step.highlights(for: service)) { highlight in
                        Label {
                            Text(highlight.text)
                        } icon: {
                            Image(systemName: highlight.systemImage)
                                .foregroundStyle(Palette.brand)
                        }
                        .font(Typography.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Spacing.large)
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.large))
            }

            if step == .account && !isConfigured {
                Label(
                    "Account connection isn't set up in this build yet (GOOGLE_CLIENT_ID is missing). You can continue without it.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(Typography.footnote)
                .foregroundStyle(Palette.warning)
            }
        }
    }
}

private struct StepIndicator: View {
    let currentIndex: Int
    let count: Int

    var body: some View {
        HStack(spacing: Spacing.small) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == currentIndex ? Palette.brand : Palette.inactive)
                    .frame(
                        width: index == currentIndex ? Layout.stepIndicatorActiveWidth : Layout.stepIndicatorDot,
                        height: Layout.stepIndicatorDot
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(currentIndex + 1) of \(count)")
    }
}

#Preview {
    OnboardingView {}
        .appEnvironment(.preview())
}
