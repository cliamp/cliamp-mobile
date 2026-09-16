import CliampCore
import CliampDesign
import SwiftUI

/// The Podcasts tab: the shows you own on top, the Apple directory below, one
/// flat scroll, paged as it runs out. Ported from Android's `PodcastsScreen`.
struct PodcastsScreen: View {
    @Environment(\.cliampPalette) private var palette
    let player: RadioPlayer
    let app: AppState
    let podcasts: PodcastsModel
    let downloads: DownloadManager
    let onOpenSettings: () -> Void
    let onOpenShow: (PodcastShow) -> Void

    @State private var pane: Pane = .all
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    enum Pane: String, CaseIterable, Identifiable {
        case all
        case subscribed
        case directory

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            CliampHeader("Podcasts", onSearch: {
                // The header key is the global search's doorway on Android;
                // until that screen lands it opens the directory's field.
                pane = .directory
                searchFocused = true
            }, onSettings: onOpenSettings) {
                chips
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if pane == .all || pane == .subscribed {
                        subscribedSection
                    }
                    if pane == .all || pane == .directory {
                        directorySection
                    }
                    Spacer().frame(height: 20)
                }
            }
        }
        .background(palette.ground)
        .task { podcasts.start() }
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(Pane.allCases) { option in
            Chip(option.rawValue, selected: pane == option) {
                pane = option
            }
        }
        Spacer().frame(width: 4)
        countryMenu
    }

    private var countryMenu: some View {
        Menu {
            Button("all countries") {
                podcasts.load(.top(country: ""), reset: true)
            }
            ForEach(podcasts.countries, id: \.iso3166) { country in
                Button(country.name) {
                    podcasts.load(.top(country: country.iso3166), reset: true)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text((currentCountryName ?? "all countries").uppercased())
                    .cliampText(CliampType.chip)
                    .foregroundStyle(currentCountryName == nil ? palette.inkTertiary : palette.onAccent)
                    .lineLimit(1)
                CliampIcon(
                    CliampIcons.caretDown, size: 8,
                    tint: currentCountryName == nil ? palette.inkTertiary : palette.onAccent
                )
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(currentCountryName == nil ? .clear : (palette.dark ? palette.accent : palette.ink))
            .clipShape(RoundedRectangle(cornerRadius: CliampShape.small))
            .overlay {
                if currentCountryName == nil {
                    RoundedRectangle(cornerRadius: CliampShape.small)
                        .stroke(palette.chipBorder, lineWidth: 1)
                }
            }
        }
    }

    private var currentCountryName: String? {
        let code = podcasts.country
        guard !code.isEmpty else { return nil }
        return podcasts.countries.first { $0.iso3166.caseInsensitiveCompare(code) == .orderedSame }?.name
            ?? code.uppercased()
    }

    // MARK: subscribed

    @ViewBuilder
    private var subscribedSection: some View {
        SectionLabel("subscribed — \(podcasts.subscriptions.count)") {
            GridListToggle(gridMode: app.subsGrid) { app.subsGrid.toggle() }
        }
        if podcasts.subscriptions.isEmpty {
            EmptyNote("nothing subscribed — open a show and hit the star")
        } else if app.subsGrid {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(podcasts.subscriptions) { show in
                    ShowTile(
                        show: show,
                        subscribed: true,
                        onOpen: { onOpenShow(show) },
                        onToggleSubscribe: { podcasts.toggleSubscription(show) }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        } else {
            ForEach(podcasts.subscriptions) { show in
                ShowRow(
                    show: show,
                    subscribed: true,
                    onOpen: { onOpenShow(show) },
                    onToggleSubscribe: { podcasts.toggleSubscription(show) }
                )
            }
        }
    }

    // MARK: directory

    @ViewBuilder
    private var directorySection: some View {
        SectionLabel("directory", gutter: cliampGutter) {
            HStack(spacing: 12) {
                Text(podcasts.query.label)
                    .cliampText(CliampType.meta)
                    .foregroundStyle(palette.inkTertiary)
                GridListToggle(gridMode: app.podcastDirectoryGrid) {
                    app.podcastDirectoryGrid.toggle()
                }
            }
        }
        directoryFilters
        searchField
        if podcasts.shows.isEmpty, podcasts.loading {
            EmptyNote("loading…")
        } else if app.podcastDirectoryGrid {
            directoryGrid
        } else {
            directoryRows
        }
        directoryFooter
    }

    private var directoryFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                Chip("top", selected: isTopQuery) {
                    podcasts.load(.top(country: podcasts.country), reset: true)
                }
                ForEach(PodcastDirectory.genres) { genre in
                    Chip(genre.name.lowercased(), selected: podcasts.query == .category(genre)) {
                        podcasts.load(.category(genre), reset: true)
                    }
                }
            }
            .padding(.leading, cliampGutter)
            .padding(.trailing, cliampGutter)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var isTopQuery: Bool {
        if case .top = podcasts.query { return true }
        return false
    }

    private var currentCountryCode: String {
        podcasts.country
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            CliampIcon(CliampIcons.search, size: 15, tint: palette.inkTertiary)
            TextField("search shows", text: $searchText)
                .cliampText(CliampType.rowPrimary)
                .foregroundStyle(palette.ink)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit(runSearch)
            if !searchText.isEmpty {
                CliampIcon(CliampIcons.xmark, size: 12, tint: palette.inkTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        searchText = ""
                        podcasts.load(.top(country: podcasts.country), reset: true)
                    }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: CliampShape.small))
        .overlay(
            RoundedRectangle(cornerRadius: CliampShape.small)
                .stroke(palette.chipBorder, lineWidth: 1)
        )
        .padding(.horizontal, cliampGutter)
        .padding(.vertical, 4)
    }

    private func runSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        podcasts.load(.search(text), reset: true)
    }

    private var directoryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(podcasts.shows) { show in
                ShowTile(
                    show: show,
                    subscribed: podcasts.isSubscribed(feedUrl: show.feedUrl),
                    onOpen: { onOpenShow(show) },
                    onToggleSubscribe: { podcasts.toggleSubscription(show) }
                )
                .onAppear { podcasts.nextPageIfNeeded(current: show) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
    }

    private var directoryRows: some View {
        ForEach(podcasts.shows) { show in
            ShowRow(
                show: show,
                subscribed: podcasts.isSubscribed(feedUrl: show.feedUrl),
                onOpen: { onOpenShow(show) },
                onToggleSubscribe: { podcasts.toggleSubscription(show) }
            )
            .onAppear { podcasts.nextPageIfNeeded(current: show) }
        }
    }

    @ViewBuilder
    private var directoryFooter: some View {
        if let error = podcasts.error {
            RetryNote("couldn't fetch the directory", prominent: podcasts.shows.isEmpty) {
                _ = error
                podcasts.load(podcasts.query, reset: true)
            }
        } else if podcasts.loading, !podcasts.shows.isEmpty {
            EmptyNote("loading more…")
        } else if podcasts.exhausted, !podcasts.shows.isEmpty {
            EmptyNote("end of \(podcasts.query.label)")
        }
    }
}
