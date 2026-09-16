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
            player.onRecordPlay = { [app] station in app.recordPlay(station) }
            // Android restores the last station to the bus but never plays it
            // unless auto-resume is on: a radio app that starts making noise
            // on launch is a bad neighbour (RAD-12).
            if let last = app.lastStation {
                if app.autoResume {
                    player.play(last)
                } else {
                    player.restore(last)
                }
            }
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
            if let index = arguments.firstIndex(of: "-cliamp-preview-palette"), index + 1 < arguments.count {
                app.palettePreference = arguments[index + 1]
            }
            #endif
        }
    }
}

#Preview {
    RootView()
}
