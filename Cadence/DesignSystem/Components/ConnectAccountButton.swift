import AuthenticationServices
import SwiftUI

/// Connects the active service: Google sign-in for YouTube, the library permission for Apple Music.
struct ConnectAccountButton: View {
    /// Explains why the button is disabled when the build is missing a key or client ID.
    var showsSetupHint = true
    var onConnected: () -> Void = {}

    @Environment(ServiceHub.self) private var hub
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openURL) private var openURL
    @State private var isConnecting = false
    @State private var error: AppError?

    var body: some View {
        let catalog = hub.catalog
        VStack(spacing: Spacing.small) {
            Button(action: connect) {
                HStack(spacing: Spacing.small) {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Image(systemName: catalog.service.systemImage)
                    }
                    Text(catalog.connectTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(isConnecting || !catalog.isConfigured)

            if showsSetupHint && !catalog.isConfigured {
                Text("Add GOOGLE_CLIENT_ID to Config/Secrets.xcconfig to enable sign-in.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .alert(error?.title ?? "", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        ), presenting: error) { error in
            // Library access that was turned off can only be turned back on in the Settings app.
            #if os(iOS)
            if error == .appleMusicAccessDenied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(settingsURL) }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
            #else
            Button("OK", role: .cancel) {}
            #endif
        } message: { error in
            Text(error.message)
        }
    }

    private func connect() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                try await hub.catalog.connect(using: webAuthenticationSession)
                onConnected()
            } catch AppError.signInCancelled {
                // The user closed the sheet; nothing to report.
            } catch {
                self.error = AppError(error)
            }
        }
    }
}
