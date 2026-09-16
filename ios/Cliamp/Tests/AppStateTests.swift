import Foundation
import Testing

@testable import Cliamp

@Suite("app state persistence")
struct AppStateTests {
    @Test("settings survive a relaunch")
    @MainActor
    func persistenceRoundTrip() {
        let suite = "app-state-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let first = AppState(defaults: defaults)
        first.palettePreference = "catppuccin"
        first.haptics = false
        first.visualizer = "off"
        first.bufferSeconds = 45
        first.autoResume = true

        let second = AppState(defaults: defaults)
        #expect(second.palettePreference == "catppuccin")
        #expect(second.haptics == false)
        #expect(second.visualizer == "off")
        #expect(second.bufferSeconds == 45)
        #expect(second.autoResume)
        #expect(second.cellular)
        #expect(!second.mono)
    }
}
