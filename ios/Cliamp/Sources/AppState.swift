import CliampCore
import Observation

/// Session state that has a home in the design but not yet a store. These
/// values persist with SET-01/DAT-01; until then they are per-launch.
@MainActor
@Observable
final class AppState {
    var palettePreference = "system"
    var haptics = true
    var visualizer = "spectrum"
    var cellular = true
    var mono = false
    var bufferSeconds = 30.0
    var autoResume = false
    var resumeLocalSongs = false
    var autoDownload = false

    private(set) var favoriteURLs: Set<String> = []

    func isFavorite(_ station: Station) -> Bool {
        favoriteURLs.contains(station.url)
    }

    func toggleFavorite(_ station: Station) {
        if favoriteURLs.contains(station.url) {
            favoriteURLs.remove(station.url)
        } else {
            favoriteURLs.insert(station.url)
        }
    }
}
