import CliampCore
import CliampDesign
import SwiftUI

/// One smart list as a page above the pager: sort chips for the on-device
/// lists, type sub-tabs for favourites, a folder picker for local songs.
/// Mirrors Android's `LibrarySmartPlaylistPane`.
struct SmartDetailScreen: View {
    @Environment(\.cliampPalette) private var palette
    @Bindable var model: LibraryModel
    let kind: LibraryModel.SmartKind
    let player: RadioPlayer
    let app: AppState
    let downloads: DownloadManager
    let podcasts: PodcastsModel
    let onBack: () -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void

    @State private var folder: String?
    @State private var pendingDelete: Station?

    var body: some View {
        VStack(spacing: 0) {
            CliampHeader(kind.label, onBack: onBack, onSearch: onOpenSearch, onSettings: onOpenSettings) {
                chips
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if visible.isEmpty {
                        Text(emptyCopy)
                            .cliampText(CliampType.rowSecondary)
                            .foregroundStyle(palette.inkFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else {
                        SectionLabel("\(kind.label) — \(visible.count)")
                        ForEach(visible, id: \.url) { station in
                            row(station)
                        }
                    }
                    Spacer().frame(height: 20)
                }
            }
        }
        .background(palette.ground)
        .onChange(of: model.folders().map(\.id)) { _, ids in
            if let folder, !ids.contains(folder) { self.folder = nil }
        }
        .alert(
            "remove from the library?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("remove", role: .destructive) {
                if let station = pendingDelete {
                    Task {
                        await model.deleteLocal(station, app: app)
                    }
                }
                pendingDelete = nil
            }
            Button("cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(pendingDelete?.name ?? "")
        }
    }

    // MARK: members

    private var members: [Station] {
        model.members(
            for: kind,
            favorites: app.favorites,
            history: app.history,
            downloads: downloads.entries.values.map(\.station)
        )
    }

    private var visible: [Station] {
        var list = members
        if kind == .localSongs, let folder {
            list = model.folderSongs(folder)
        }
        if kind == .localSongs || kind == .downloads {
            list = model.sort(for: kind).apply(list)
        }
        return list
    }

    private var emptyCopy: String {
        switch kind {
        case .favorites:
            switch model.favScope {
            case .all: "no favourites yet"
            case .local: "no local favourites yet"
            case .stations: "no station favourites yet"
            case .pods: "no podcast favourites yet"
            }
        case .localSongs:
            model.loading ? "scanning for songs…" : "no songs on the phone yet"
        case .downloads:
            model.loading ? "scanning for songs…" : "no downloads yet"
        case .recentlyPlayed:
            "nothing played recently"
        }
    }

    // MARK: chips

    @ViewBuilder
    private var chips: some View {
        switch kind {
        case .favorites:
            ForEach(LibraryModel.FavScope.allCases) { scope in
                Chip(scope.label, selected: model.favScope == scope) {
                    model.favScope = scope
                }
            }
        case .localSongs:
            sortChips
            folderMenu
        case .downloads:
            sortChips
        case .recentlyPlayed:
            EmptyView()
        }
    }

    private var sortChips: some View {
        ForEach(StationSort.allCases, id: \.self) { sort in
            Chip(sortLabel(sort), selected: model.sort(for: kind) == sort) {
                model.setSort(sort, for: kind)
            }
        }
    }

    private func sortLabel(_ sort: StationSort) -> String {
        sort == .recentlyAdded ? "recent" : sort.rawValue
    }

    private var folderMenu: some View {
        let folders = model.folders()
        return Menu {
            Button("all folders") { folder = nil }
            ForEach(folders) { item in
                Button(item.name) { folder = item.id }
            }
        } label: {
            HStack(spacing: 5) {
                Text((folders.first { $0.id == folder }?.name ?? "all folders").uppercased())
                    .cliampText(CliampType.chip)
                    .foregroundStyle(folder == nil ? palette.inkTertiary : palette.onAccent)
                    .lineLimit(1)
                CliampIcon(
                    CliampIcons.caretDown, size: 8,
                    tint: folder == nil ? palette.inkTertiary : palette.onAccent
                )
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(folder == nil ? .clear : (palette.dark ? palette.accent : palette.ink))
            .clipShape(RoundedRectangle(cornerRadius: CliampShape.small))
            .overlay {
                if folder == nil {
                    RoundedRectangle(cornerRadius: CliampShape.small)
                        .stroke(palette.chipBorder, lineWidth: 1)
                }
            }
        }
        .disabled(folders.isEmpty)
    }

    // MARK: rows

    private func row(_ station: Station) -> some View {
        let active = player.station?.url == station.url
        let local = kind == .localSongs || kind == .downloads
        let favorite = app.favoriteURLs.contains(station.url)
        return ListRow(
            onClick: {
                player.play(station, from: visible, contextKey: contextKey)
            },
            leading: {
                cover(station, active: active, fallback: coverFallback(station, local: local))
            },
            trailing: {
                HStack(spacing: 10) {
                    if local {
                        Menu {
                            Button("remove", role: .destructive) {
                                if kind == .downloads {
                                    downloads.remove(url: station.url)
                                } else {
                                    pendingDelete = station
                                }
                            }
                        } label: {
                            CliampIcon(CliampIcons.more, size: 16, tint: palette.inkTertiary)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                    }
                    CliampIcon(
                        favorite ? CliampIcons.starFilled : CliampIcons.star,
                        size: 15,
                        tint: favorite ? palette.accent : palette.inkFaint
                    )
                    .microPress { app.toggleFavorite(station) }
                }
            },
            verticalPadding: 9,
            rail: active
        ) {
            Text(station.name)
                .cliampText(CliampType.rowPrimary)
                .foregroundStyle(active ? palette.accent : palette.ink)
                .lineLimit(1)
            Text(subtitle(station, local: local))
                .cliampText(CliampType.rowSecondary)
                .foregroundStyle(resumed(station, local: local) != nil ? palette.amber : palette.inkTertiary)
                .lineLimit(1)
        }
    }

    /// A row's artwork with the current-item badge, shared by every list here.
    private func cover(_ station: Station, active: Bool, fallback: StationArtFallback) -> some View {
        StationArtView(station: station, size: 40, fallback: fallback)
            .overlay {
                if active {
                    CliampIcon(
                        player.playing ? CliampIcons.pause : CliampIcons.playRow,
                        size: 9,
                        tint: palette.onAccent
                    )
                    .frame(width: 18, height: 18)
                    .background(palette.accent.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: CliampShape.tiny))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
    }

    private var contextKey: String {
        "library:\(kind.rawValue):\(folder ?? "-"):\(model.favScope.rawValue)"
    }

    private func coverFallback(_ station: Station, local: Bool) -> StationArtFallback {
        if local || station.source == .local { return .music }
        return station.source == .podcast ? .podcast : .glyph
    }

    private func resumed(_ station: Station, local: Bool) -> EpisodeProgress? {
        guard local, app.resumeLocalSongs else { return nil }
        guard let entry = podcasts.progressEntry(for: station.url),
              !entry.completed, entry.positionMs > 0
        else { return nil }
        return entry
    }

    private func subtitle(_ station: Station, local: Bool) -> String {
        var parts: [String] = []
        switch station.source {
        case .podcast:
            parts.append(station.artist.isEmpty ? (station.meta.isEmpty ? "podcast" : station.meta) : station.artist)
        case .local:
            parts.append(station.artistAlbum.isEmpty ? station.meta : station.artistAlbum)
        default:
            if !station.meta.isEmpty { parts.append(station.meta) }
            parts.append(contentsOf: station.tagList.prefix(2))
        }
        if let entry = resumed(station, local: local) {
            parts.append("\(Int(entry.fraction * 100))% in")
        }
        if kind == .downloads, let entry = downloads.entry(for: station.url) {
            parts.append(downloadSizeLabel(entry.bytes))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One user playlist as a page. With `adding` it swaps the member list for the
/// add-songs picker, exactly like Android's `PlaylistDetailShown`.
struct PlaylistDetailScreen: View {
    @Environment(\.cliampPalette) private var palette
    @Bindable var model: LibraryModel
    let slug: String
    let player: RadioPlayer
    let app: AppState
    let downloads: DownloadManager
    let podcasts: PodcastsModel
    let adding: Bool
    let onBack: () -> Void
    let onAdded: () -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        let playlist = model.playlist(slug: slug)
        VStack(spacing: 0) {
            CliampHeader(
                playlist?.name ?? "playlist",
                onBack: onBack,
                onSearch: onOpenSearch,
                onSettings: onOpenSettings
            ) {
                if !adding, playlist != nil {
                    ForEach(StationSort.allCases, id: \.self) { sort in
                        Chip(sort == .recentlyAdded ? "recent" : sort.rawValue,
                             selected: model.sort(for: .localSongs) == sort) {
                            model.setSort(sort, for: .localSongs)
                        }
                    }
                }
            }
            if let playlist, adding {
                AddSongsView(
                    playlist: playlist,
                    model: model,
                    app: app,
                    podcasts: podcasts,
                    onDone: onAdded
                )
            } else if let playlist {
                membersList(playlist)
            } else {
                Text("no such playlist")
                    .cliampText(CliampType.rowSecondary)
                    .foregroundStyle(palette.inkFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                Spacer()
            }
        }
        .background(palette.ground)
    }

    private func membersList(_ playlist: Playlist) -> some View {
        let members = model.members(slug: playlist.slug)
        let visible = model.sort(for: .localSongs).apply(members)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if members.isEmpty {
                    Text("empty — tap add")
                        .cliampText(CliampType.rowSecondary)
                        .foregroundStyle(palette.inkFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    SectionLabel("songs — \(members.count)")
                    ForEach(visible, id: \.id) { station in
                        memberRow(station, visible: visible)
                    }
                }
                Spacer().frame(height: 20)
            }
        }
        .onAppear {
            // Members load when the pane opens, the way Android resolves them
            // against the live library at open time.
            model.reloadPlaylists()
        }
    }

    private func memberRow(_ station: Station, visible: [Station]) -> some View {
        let active = player.station?.url == station.url
        return ListRow(
            onClick: {
                player.play(station, from: visible, contextKey: "playlist:\(slug)")
            },
            leading: {
                StationArtView(station: station, size: 40, fallback: coverFallback(station))
                    .overlay {
                        if active {
                            CliampIcon(
                                player.playing ? CliampIcons.pause : CliampIcons.playRow,
                                size: 9,
                                tint: palette.onAccent
                            )
                            .frame(width: 18, height: 18)
                            .background(palette.accent.opacity(0.92))
                            .clipShape(RoundedRectangle(cornerRadius: CliampShape.tiny))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        }
                    }
            },
            trailing: {
                Text("DROP")
                    .cliampText(CliampType.tabLabel)
                    .foregroundStyle(palette.destructiveInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .microPress {
                        model.removeMember(slug: slug, songId: station.id)
                    }
            },
            verticalPadding: 9,
            rail: active
        ) {
            Text(station.name)
                .cliampText(CliampType.rowPrimary)
                .foregroundStyle(active ? palette.accent : palette.ink)
                .lineLimit(1)
            Text(station.artistAlbum.isEmpty ? fallbackSubtitle(station) : station.artistAlbum)
                .cliampText(CliampType.rowSecondary)
                .foregroundStyle(palette.inkTertiary)
                .lineLimit(1)
        }
    }

    private func coverFallback(_ station: Station) -> StationArtFallback {
        if station.source == .local { return .music }
        return station.source == .podcast ? .podcast : .glyph
    }

    private func fallbackSubtitle(_ station: Station) -> String {
        switch station.source {
        case .local: station.durationMs > 0 ? TimeFormat.clock(station.durationMs) : "local audio"
        case .podcast: "podcast"
        default: station.meta
        }
    }
}

/// The add-songs picker: local songs, radio stations and podcast episodes in
/// their own sub-tabs with one shared selection. Mirrors Android's
/// `AddSongsPicker`.
struct AddSongsView: View {
    @Environment(\.cliampPalette) private var palette
    let playlist: Playlist
    let model: LibraryModel
    let app: AppState
    let podcasts: PodcastsModel
    let onDone: () -> Void

    private enum AddTab: String, CaseIterable, Identifiable {
        case local, stations, podcasts
        var id: String { rawValue }
    }

    @State private var tab: AddTab = .local
    @State private var picked: Set<String> = []
    @State private var openShow: PodcastShow?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(playlist.name)
                    .cliampText(CliampType.chip)
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(picked.count) selected")
                    .cliampText(CliampType.meta)
                    .foregroundStyle(palette.inkTertiary)
                Chip("done", selected: false, action: onDone)
            }
            .padding(.horizontal, cliampGutter)
            .padding(.vertical, 6)
            HStack(spacing: 7) {
                ForEach(AddTab.allCases) { option in
                    Chip(option.rawValue, selected: tab == option) {
                        tab = option
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, cliampGutter)
            .padding(.bottom, 4)
            HairlineDivider(region: true)
            list
        }
        .onAppear { picked = Set(playlist.songIds) }
    }

    @ViewBuilder
    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch tab {
                case .local:
                    ForEach(model.songs, id: \.id) { station in
                        toggleRow(station, subtitle: station.artistAlbum.isEmpty
                            ? (station.durationMs > 0 ? TimeFormat.clock(station.durationMs) : "local audio")
                            : station.artistAlbum)
                    }
                    if model.songs.isEmpty {
                        emptyNote("no local songs yet")
                    }
                case .stations:
                    ForEach(model.addableStations(favorites: app.favorites, history: app.history), id: \.id) { station in
                        toggleRow(station, subtitle: station.meta)
                    }
                case .podcasts:
                    podcastList
                }
                Spacer().frame(height: 20)
            }
        }
    }

    @ViewBuilder
    private var podcastList: some View {
        if let show = openShow {
            SectionLabel(show.title) {
                Text("back")
                    .cliampText(CliampType.tabLabel)
                    .foregroundStyle(palette.accent)
                    .microPress { openShow = nil }
            }
            ForEach(podcasts.episodes, id: \.audioUrl) { episode in
                toggleRow(episode.station(show: show), subtitle: episode.listMeta)
            }
            if podcasts.showLoading, podcasts.episodes.isEmpty {
                emptyNote("loading…")
            } else if podcasts.episodes.isEmpty {
                emptyNote("no episodes yet")
            }
        } else if podcasts.subscriptions.isEmpty {
            emptyNote("no subscribed shows yet")
        } else {
            ForEach(podcasts.subscriptions, id: \.feedUrl) { show in
                ListRow(
                    onClick: {
                        openShow = show
                        podcasts.openShow(show)
                    },
                    leading: { StationArtView(station: show.artStation, size: 40, fallback: .podcast) },
                    verticalPadding: 8
                ) {
                    Text(show.title)
                        .cliampText(CliampType.rowPrimary)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(show.meta)
                        .cliampText(CliampType.rowSecondary)
                        .foregroundStyle(palette.inkTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func toggleRow(_ station: Station, subtitle: String) -> some View {
        let selected = picked.contains(station.id)
        return ListRow(
            onClick: {
                if selected {
                    picked.remove(station.id)
                    model.removeMember(slug: playlist.slug, songId: station.id)
                } else {
                    picked.insert(station.id)
                    model.addStation(slug: playlist.slug, station: station)
                }
            },
            leading: { StationArtView(station: station, size: 40, fallback: .music) },
            trailing: {
                CliampIcon(
                    CliampIcons.check,
                    size: 13,
                    tint: selected ? palette.accent : palette.inkFaint.opacity(0.4)
                )
            },
            verticalPadding: 8
        ) {
            Text(station.name)
                .cliampText(CliampType.rowPrimary)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Text(subtitle)
                .cliampText(CliampType.rowSecondary)
                .foregroundStyle(palette.inkTertiary)
                .lineLimit(1)
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .cliampText(CliampType.rowSecondary)
            .foregroundStyle(palette.inkFaint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

/// The providers pane: the connected accounts. Provider protocols land with
/// their own slice (DEC-05), so the honest empty state is all there is now —
/// the same note Android shows before its first account.
struct ProvidersPane: View {
    @Environment(\.cliampPalette) private var palette
    let onBack: () -> Void
    let onOpenSearch: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            CliampHeader("providers", onBack: onBack, onSearch: onOpenSearch, onSettings: onOpenSettings) {
                EmptyView()
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    SectionLabel("connected — 0") {
                        EmptyView()
                    }
                    Text("nothing connected yet")
                        .cliampText(CliampType.rowSecondary)
                        .foregroundStyle(palette.inkFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, cliampGutter)
                        .padding(.vertical, 8)
                    Spacer().frame(height: 20)
                }
            }
        }
        .background(palette.ground)
    }
}
