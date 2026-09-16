import CliampCore
import Foundation
import CliampDesign
import SwiftUI

struct RootView: View {
    @Environment(\.colorScheme) private var systemScheme
    @State private var app = AppState()
    @State private var player = RadioPlayer()
    @State private var tab: AppTab = .stations
    @State private var showSettings = false
    @State private var showPlayer = false

    var body: some View {
        let palette = cliampPalette(for: app.palettePreference, systemDark: systemScheme == .dark)
        MainShell(
            tab: $tab,
            player: player,
            app: app,
            onOpenSettings: { showSettings = true },
            onOpenPlayer: { showPlayer = true }
        )
        .cliampTheme(palette)
        .environment(\.cliampHapticsEnabled, app.haptics)
        .fullScreenCover(isPresented: $showSettings) {
            SettingsScreen(app: app, onBack: { showSettings = false })
                .cliampTheme(palette)
                .environment(\.cliampHapticsEnabled, app.haptics)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            NowPlayingScreen(player: player, app: app, onClose: { showPlayer = false })
                .cliampTheme(palette)
                .environment(\.cliampHapticsEnabled, app.haptics)
        }
        .task {
            #if DEBUG
            // Preview hooks for screenshots and UI tests; never compiled into
            // release builds.
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-cliamp-preview-player") {
                player.play(CliampRadio.builtin[0])
                showPlayer = true
            }
            if arguments.contains("-cliamp-preview-playing") {
                player.play(CliampRadio.builtin[0])
            }
            if let index = arguments.firstIndex(of: "-cliamp-preview-url"), index + 1 < arguments.count,
               let station = Station.custom(name: "preview", url: arguments[index + 1])
            {
                player.play(station)
                showPlayer = true
            }
            if arguments.contains("-cliamp-preview-settings") {
                showSettings = true
            }
            #endif
        }
    }
}

#Preview {
    RootView()
}
