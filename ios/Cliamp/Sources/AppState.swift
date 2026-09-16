import CliampCore
import Foundation
import Observation

/// Session state that persists across launches. Auto-resume, resume-local,
/// auto-download, mono and the buffer still await their audible behavior, but
/// their storage is real from here on (SET-01/DAT-01).
@MainActor
@Observable
final class AppState {
    var palettePreference: String { didSet { defaults.set(palettePreference, forKey: Keys.palette) } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: Keys.haptics) } }
    var visualizer: String { didSet { defaults.set(visualizer, forKey: Keys.visualizer) } }
    var cellular: Bool { didSet { defaults.set(cellular, forKey: Keys.cellular) } }
    var mono: Bool { didSet { defaults.set(mono, forKey: Keys.mono) } }
    var bufferSeconds: Double { didSet { defaults.set(bufferSeconds, forKey: Keys.buffer) } }
    var autoResume: Bool { didSet { defaults.set(autoResume, forKey: Keys.autoResume) } }
    var resumeLocalSongs: Bool { didSet { defaults.set(resumeLocalSongs, forKey: Keys.resumeLocal) } }
    var autoDownload: Bool { didSet { defaults.set(autoDownload, forKey: Keys.autoDownload) } }

    private(set) var favoriteURLs: Set<String> = []

    private let defaults: UserDefaults

    private enum Keys {
        static let palette = "palette"
        static let haptics = "haptics"
        static let visualizer = "visualizer"
        static let cellular = "cellular"
        static let mono = "mono"
        static let buffer = "buffer_seconds"
        static let autoResume = "auto_resume"
        static let resumeLocal = "resume_local_songs"
        static let autoDownload = "auto_download"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        palettePreference = defaults.string(forKey: Keys.palette) ?? "system"
        haptics = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        visualizer = defaults.string(forKey: Keys.visualizer) ?? "spectrum"
        cellular = defaults.object(forKey: Keys.cellular) as? Bool ?? true
        mono = defaults.bool(forKey: Keys.mono)
        bufferSeconds = defaults.object(forKey: Keys.buffer) as? Double ?? 30
        autoResume = defaults.bool(forKey: Keys.autoResume)
        resumeLocalSongs = defaults.bool(forKey: Keys.resumeLocal)
        autoDownload = defaults.bool(forKey: Keys.autoDownload)
    }

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
