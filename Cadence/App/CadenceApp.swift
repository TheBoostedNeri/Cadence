import SwiftUI

@main
struct CadenceApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            RootView()
                .appEnvironment(environment)
        }
        .commands {
            AppCommands(player: environment.player, router: environment.router)
        }
        #else
        // A single window: there's one player, and it can only be on screen in one place.
        Window("Cadence", id: "main") {
            RootView()
                .appEnvironment(environment)
                .frame(minWidth: Layout.macWindowMinWidth, minHeight: Layout.macWindowMinHeight)
        }
        .defaultSize(width: Layout.macWindowDefaultWidth, height: Layout.macWindowDefaultHeight)
        .commands {
            AppCommands(player: environment.player, router: environment.router)
        }

        Settings {
            AccountView()
                .appEnvironment(environment)
                .frame(width: Layout.macSettingsWidth, height: Layout.macSettingsHeight)
        }
        #endif
    }
}
