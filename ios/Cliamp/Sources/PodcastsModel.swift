import CliampCore
import Foundation
import Observation
import os

/// Podcasts, held the way StationsModel holds radio: a small resident list you
/// own (subscriptions) beside a directory that is paged and never fully
/// materialised. Ported from Android's `PodcastRepository`.
@MainActor
@Observable
final class PodcastsModel {
    enum Query: Equatable {
        /// An empty country is "all countries", resolved as Apple's global chart.
        case top(country: String)
        case search(String)
        case category(PodcastGenre)

        var label: String {
            switch self {
            case .top: "top shows"
            case .search(let text): "\"\(text)\""
            case .category(let genre): genre.name.lowercased()
            }
        }

        var key: String {
            switch self {
            case .top(let country):
                "podcasts:top:\(country.isEmpty ? "all" : country.lowercased())"
            case .search(let text): "podcasts:search:\(text.trimmingCharacters(in: .whitespaces).lowercased())"
            case .category(let genre): "podcasts:cat:\(genre.id)"
            }
        }
    }

    private(set) var query: Query = .top(country: "us")
    private(set) var shows: [PodcastShow] = []
    private(set) var loading = false
    private(set) var exhausted = false
    private(set) var error: String?
    private(set) var subscriptions: [PodcastShow] = []
    private(set) var progress: [String: EpisodeProgress] = [:]
    private(set) var countries: [CountryCount] = []

    private(set) var show: PodcastShow?
    private(set) var episodes: [PodcastEpisode] = []
    private(set) var showLoading = false
    private(set) var showError: String?

    let store: PodcastStore
    /// Set by PodcastServices so a feed refresh can fire auto-downloads.
    weak var downloads: DownloadManager?

    private let directoryTransport: PodcastDirectoryTransport
    private let feedTransport: PodcastFeedTransport
    private let countryClient: RadioBrowserClient
    private let log = Logger(subsystem: "stream.cliamp.mobile", category: "podcasts")
    private var started = false
    private var chartCursor: [String] = []
    private var chartQueue: [@Sendable () async throws -> [String]] = []
    private var pending: [PodcastShow] = []
    private let pageSize = 30
    /// Bumped by every reset so a slow page from an older query cannot write
    /// into the newer one's state.
    private var generation = 0

    init(
        store: PodcastStore = .applicationDefault(),
        directoryTransport: PodcastDirectoryTransport = URLSessionPodcastTransport(),
        feedTransport: PodcastFeedTransport = URLSessionPodcastFeedTransport(),
        countryClient: RadioBrowserClient = RadioBrowserClient()
    ) {
        self.store = store
        self.directoryTransport = directoryTransport
        self.feedTransport = feedTransport
        self.countryClient = countryClient
    }

    func start() {
        guard !started else { return }
        started = true
        reloadLibrary()
        load(.top(country: "us"), reset: true)
        Task { countries = await countryClient.topCountries() }
    }

    func reloadLibrary() {
        subscriptions = store.subscriptions()
        progress = store.progress()
    }

    // MARK: directory

    func load(_ query: Query, reset: Bool) {
        if reset {
            generation += 1
        }
        let token = generation
        log.info("load \(query.key, privacy: .public) reset \(reset, privacy: .public) token \(token, privacy: .public)")
        Task { await loadPage(query, reset: reset, token: token) }
    }

    func nextPage() {
        load(query, reset: false)
    }

    /// Fetches the next page when the last visible row comes into view.
    func nextPageIfNeeded(current: PodcastShow) {
        guard !loading, !exhausted, error == nil else { return }
        guard let index = shows.firstIndex(of: current), index >= shows.count - 8 else { return }
        nextPage()
    }

    private func loadPage(_ query: Query, reset: Bool, token: Int) async {
        if !reset, loading || exhausted || error != nil { return }
        if reset {
            self.query = query
            loading = true
            exhausted = false
            error = nil
            chartCursor = []
            chartQueue = []
            pending = []
            // Fill the screen from the last snapshot of this query while the
            // network answers; the first live page replaces it.
            if shows.isEmpty, let snapshot = store.directorySnapshot(key: query.key) {
                shows = snapshot
            }
            let country = { if case .top(let c) = query { return c.isEmpty ? "us" : c } else { return "us" } }()
            do {
                try Task.checkCancellation()
                switch query {
                case .top:
                    chartCursor = try await PodcastDirectory.chartIds(
                        country: country, transport: directoryTransport
                    )
                    for genre in PodcastDirectory.genres {
                        chartQueue.append { [directoryTransport] in
                            try await PodcastDirectory.chartIds(
                                country: country, genreId: genre.id, transport: directoryTransport
                            )
                        }
                    }
                case .search(let text):
                    pending = try await PodcastDirectory.search(term: text, transport: directoryTransport)
                case .category(let genre):
                    pending = try await PodcastDirectory.byGenre(genre, transport: directoryTransport)
                }
                guard token == generation else { return }
            } catch {
                loading = false
                // A snapshot already on screen is better than an error.
                if shows.isEmpty {
                    self.error = error.localizedDescription
                }
                return
            }
        }

        do {
            let list: [PodcastShow]
            if !chartCursor.isEmpty || !chartQueue.isEmpty {
                if chartCursor.isEmpty {
                    chartCursor = try await chartQueue.removeFirst()()
                    guard token == generation else { return }
                }
                let ids = Array(chartCursor.prefix(pageSize))
                // Only consume ids once they resolve: a failed page is
                // retried, never silently skipped.
                let resolved = try await PodcastDirectory.lookup(ids: ids, transport: directoryTransport)
                guard token == generation else { return }
                chartCursor.removeFirst(min(ids.count, chartCursor.count))
                list = resolved
            } else {
                let slice = Array(pending.prefix(pageSize))
                pending.removeFirst(min(slice.count, pending.count))
                list = slice
            }
            let base = reset ? [] : shows
            var seen = Set(base.map(\.feedUrl))
            shows = base + list.filter { seen.insert($0.feedUrl).inserted }
            exhausted = chartCursor.isEmpty && chartQueue.isEmpty && pending.isEmpty
            loading = false
            error = nil
            if reset {
                store.saveDirectorySnapshot(shows, key: query.key)
            }
        } catch {
            loading = false
            self.error = error.localizedDescription
        }
    }

    // MARK: subscriptions

    func isSubscribed(feedUrl: String) -> Bool {
        subscriptions.contains { $0.feedUrl == feedUrl }
    }

    /// Returns the new state, so a row can toggle without re-reading.
    @discardableResult
    func toggleSubscription(_ show: PodcastShow) -> Bool {
        let subscribed = store.toggleSubscription(show)
        reloadLibrary()
        return subscribed
    }

    // MARK: one show

    /// Loads `show`'s feed. The show is published before the fetch so the
    /// episode screen can draw its header immediately, and a fresh cached feed
    /// fills the list while the network answers.
    func openShow(_ show: PodcastShow, force: Bool = false) {
        if !force, self.show?.feedUrl == show.feedUrl, !episodes.isEmpty, !showLoading {
            return
        }
        self.show = show
        episodes = []
        showLoading = true
        showError = nil
        Task {
            if let cached = store.freshFeed(feedUrl: show.feedUrl), episodes.isEmpty {
                self.show = cached.show
                episodes = cached.episodes
            }
            do {
                let loaded = try await PodcastFeed.load(show: show, transport: feedTransport)
                self.show = loaded.show
                episodes = loaded.episodes
                showLoading = false
                store.saveFeed(loaded.show, episodes: loaded.episodes)
                // A subscription keeps whatever the feed knows that the
                // directory did not, so the list stops looking half-filled.
                if store.isSubscribed(feedUrl: loaded.show.feedUrl) {
                    store.updateSubscription(loaded.show)
                    reloadLibrary()
                }
                downloads?.autoDownload(
                    show: loaded.show,
                    episodes: loaded.episodes,
                    completedUrls: completedURLs
                )
            } catch {
                showLoading = false
                if episodes.isEmpty {
                    showError = error.localizedDescription
                }
            }
        }
    }

    func refreshShow() {
        guard let show else { return }
        openShow(show, force: true)
    }

    // MARK: progress

    var completedURLs: Set<String> {
        Set(progress.filter { $0.value.completed }.keys)
    }

    func progressEntry(for url: String) -> EpisodeProgress? {
        progress[url]
    }

    /// Where playback should start; live radio is not a track and starts at 0.
    /// The in-memory map is authoritative when loaded; a cold open that never
    /// visited the tab reads the store once for this URL.
    func resumePosition(_ station: Station) -> Int64 {
        guard station.isTrack else { return 0 }
        if let entry = progress[station.url] {
            return PodcastProgress.resumePosition(entry)
        }
        guard let stored = store.progress()[station.url] else { return 0 }
        progress[station.url] = stored
        return PodcastProgress.resumePosition(stored)
    }

    func saveProgress(_ station: Station, positionMs: Int64, durationMs: Int64) {
        guard station.isTrack, positionMs > 0 else { return }
        let entry = EpisodeProgress(
            url: station.url,
            positionMs: positionMs,
            durationMs: durationMs,
            completed: PodcastProgress.isCompleted(positionMs: positionMs, durationMs: durationMs),
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        store.saveProgress(entry)
        progress[entry.url] = entry
    }

    func markCompleted(_ station: Station) {
        let duration = station.durationMs > 0 ? station.durationMs : (progress[station.url]?.durationMs ?? 0)
        let entry = EpisodeProgress(
            url: station.url,
            positionMs: duration,
            durationMs: duration,
            completed: true,
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        store.saveProgress(entry)
        progress[entry.url] = entry
    }

    func clearProgress(_ station: Station) {
        store.clearProgress(url: station.url)
        progress.removeValue(forKey: station.url)
    }
}

/// One process-wide owner for the podcast store, model and download manager,
/// so view rebuilds cannot duplicate them.
@MainActor
final class PodcastServices {
    static let shared = PodcastServices()

    let store: PodcastStore
    let podcasts: PodcastsModel
    let downloads: DownloadManager

    private init() {
        store = .applicationDefault()
        podcasts = PodcastsModel(store: store)
        downloads = DownloadManager(store: store, allowsCellular: {
            UserDefaults.standard.object(forKey: "cellular") as? Bool ?? true
        })
        podcasts.downloads = downloads
    }
}
