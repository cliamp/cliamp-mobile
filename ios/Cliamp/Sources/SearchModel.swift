import CliampCore
import Foundation
import Observation
import os

/// One result in the app-wide finder. Only the sources that exist today
/// produce hits; local, tags and providers light up with phases 3 and 5.
enum SearchHit: Identifiable, Hashable {
    case show(PodcastShow)
    case episode(PodcastShow, PodcastEpisode)
    case station(Station)

    var id: String {
        switch self {
        case .show(let show): "show:\(show.feedUrl)"
        case .episode(let show, let episode): "ep:\(show.id):\(episode.guid)"
        case .station(let station): "station:\(station.url)"
        }
    }
}

/// The app-wide fuzzy finder's state: one query spanning whatever catalogs are
/// available, with the Android `SearchScope` chips.
@MainActor
@Observable
final class SearchModel {
    enum Scope: String, CaseIterable, Identifiable {
        case all
        case local
        case radio
        case podcasts
        case tags
        case providers

        var id: String { rawValue }
    }

    var query = "" {
        didSet { scheduleSearch() }
    }

    private(set) var scope: Scope = .all
    private(set) var hits: [SearchHit] = []
    private(set) var searching = false
    private(set) var term = ""

    /// Favourites live in AppState; injected so this model stays store-free.
    var favoritesProvider: (() -> [Station])?

    private let podcasts: PodcastsModel
    private let customStore = CustomStationStore()
    private let radioClient = RadioBrowserClient()
    private let log = Logger(subsystem: "stream.cliamp.mobile", category: "search")
    private var searchTask: Task<Void, Never>?

    init(podcasts: PodcastsModel) {
        self.podcasts = podcasts
    }

    func setScope(_ scope: Scope) {
        self.scope = scope
        scheduleSearch()
    }

    func clear() {
        query = ""
        hits = []
        term = ""
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            hits = []
            term = ""
            searching = false
            return
        }
        searching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.run(term: text)
        }
    }

    private func run(term text: String) async {
        let lowered = text.lowercased()
        var results: [SearchHit] = []

        if scope == .all || scope == .podcasts {
            // Subscribed shows' cached episodes answer offline; the directory
            // answers online.
            for (show, episode) in podcasts.store.subscribedEpisodes()
            where episode.title.lowercased().contains(lowered) {
                results.append(.episode(show, episode))
            }
            if let shows = try? await PodcastDirectory.search(term: text) {
                results.append(contentsOf: shows.prefix(20).map { .show($0) })
            }
        }

        if scope == .all || scope == .radio {
            let known = (CliampRadio.builtin + customStore.load() + (favoritesProvider?() ?? []))
                .filter { $0.name.lowercased().contains(lowered) }
            results.append(contentsOf: known.prefix(20).map { .station($0) })
            if let stations = try? await radioClient.stations(
                for: .search(text), offset: 0, limit: 20
            ) {
                results.append(contentsOf: stations.map { .station($0) })
            }
        }

        // Local library, radio tags and provider catalogs arrive with phases
        // 3 and 5; until then those chips honestly have nothing to show.
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        hits = results.filter { seen.insert($0.id).inserted }
        term = text
        searching = false
        log.info("search \(text, privacy: .public) scope \(self.scope.rawValue, privacy: .public) hits \(self.hits.count, privacy: .public)")
    }
}
