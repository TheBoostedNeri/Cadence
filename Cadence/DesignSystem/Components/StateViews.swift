import SwiftUI

struct LoadingStateView: View {
    private let message: LocalizedStringKey

    init(_ message: LocalizedStringKey) {
        self.message = message
    }

    var body: some View {
        VStack(spacing: Spacing.medium) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.stateMinimumHeight)
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            actions
                .frame(maxWidth: Layout.buttonMaxWidth)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.stateMinimumHeight)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

/// Explains an `AppError` and offers the most useful next step: connecting an account or retrying.
struct ErrorStateView: View {
    let error: AppError
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(error.title, systemImage: error.systemImage)
        } description: {
            Text(error.message)
        } actions: {
            Group {
                if error.offersAccountConnection {
                    ConnectAccountButton()
                } else if let retry, error.isRetryable {
                    Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                        .buttonStyle(.glassProminent)
                }
            }
            .frame(maxWidth: Layout.buttonMaxWidth)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.stateMinimumHeight)
    }
}

/// A compact error card for one section of a screen, so the rest of the screen stays usable.
struct InlineErrorView: View {
    let error: AppError
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            Image(systemName: error.systemImage)
                .font(Typography.headline)
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(error.title)
                    .font(Typography.headline)
                Text(error.message)
                    .font(Typography.footnote)
                    .foregroundStyle(Palette.textSecondary)
                if let retry, error.isRetryable {
                    Button("Try Again", action: retry)
                        .font(Typography.sectionAction)
                        .buttonStyle(.borderless)
                        .padding(.top, Spacing.xSmall)
                }
            }
            Spacer(minLength: Spacing.none)
        }
        .padding(Spacing.large)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.large))
    }
}

/// Holds a shelf's place while its content loads.
struct ShelfLoadingView: View {
    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, minHeight: ArtworkSize.card)
            .accessibilityLabel("Loading")
    }
}

extension View {
    /// Presents an alert whenever `error` is non-nil and clears it on dismissal.
    func errorAlert(_ error: Binding<AppError?>) -> some View {
        alert(
            error.wrappedValue?.title ?? "",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { isPresented in if !isPresented { error.wrappedValue = nil } }
            ),
            presenting: error.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}
