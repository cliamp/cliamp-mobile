import CliampCore
import CliampDesign
import SwiftUI

/// The app-wide finder: one query across the catalogs that exist, over the
/// permanent chrome so the mini player and tab bar stay visible. Ported from
/// Android's `SearchScreen`.
struct SearchScreen: View {
    @Environment(\.cliampPalette) private var palette
    let model: SearchModel
    let player: RadioPlayer
    let onBack: () -> Void
    let onOpenShow: (PodcastShow) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            scopeChips
            HairlineDivider(region: true)
            results
        }
        .background(palette.ground)
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            BackChevron { onBack() }
            HStack(spacing: 8) {
                CliampIcon(CliampIcons.search, size: 15, tint: palette.inkTertiary)
                TextField("Search", text: Binding(
                    get: { model.query },
                    set: { model.query = $0 }
                ))
                .cliampText(CliampType.rowPrimary)
                .foregroundStyle(palette.ink)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($focused)
                if !model.query.isEmpty {
                    CliampIcon(CliampIcons.xmark, size: 12, tint: palette.inkTertiary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                        .onTapGesture { model.clear() }
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
        }
        .padding(.horizontal, cliampGutter)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(SearchModel.Scope.allCases) { scope in
                    Chip(scope.rawValue, selected: model.scope == scope) {
                        model.setScope(scope)
                    }
                }
            }
            .padding(.horizontal, cliampGutter)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var results: some View {
        if model.hits.isEmpty, !model.term.isEmpty {
            VStack {
                Text("no hits anywhere for \"\(model.term)\"")
                    .cliampText(CliampType.rowSecondary)
                    .foregroundStyle(palette.inkFaint)
                    .padding(.horizontal, cliampGutter)
                    .padding(.vertical, 20)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sections, id: \.title) { section in
                        SectionLabel(section.title) { EmptyView() }
                        ForEach(section.hits) { hit in
                            row(hit)
                        }
                    }
                    Spacer().frame(height: 12)
                }
            }
        }
    }

    private var sections: [(title: String, hits: [SearchHit])] {
        var order: [String] = []
        var grouped: [String: [SearchHit]] = [:]
        for hit in model.hits {
            let section = switch hit {
            case .show, .episode: "podcasts — global"
            case .station: "radio — global"
            }
            if grouped[section] == nil { order.append(section) }
            grouped[section, default: []].append(hit)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    @ViewBuilder
    private func row(_ hit: SearchHit) -> some View {
        switch hit {
        case .show(let show):
            searchRow(
                art: show.artStation,
                title: show.title,
                subtitle: show.meta.isEmpty ? "podcast" : show.meta
            ) {
                onOpenShow(show)
            }
        case .episode(let show, let episode):
            searchRow(
                art: episode.station(show: show),
                title: episode.title,
                subtitle: show.title
            ) {
                play(episode.station(show: show), from: episodeStations)
            }
        case .station(let station):
            searchRow(
                art: station,
                title: station.name,
                subtitle: station.sourceLine
            ) {
                play(station, from: stationStations)
            }
        }
    }

    private var episodeStations: [Station] {
        model.hits.compactMap { hit in
            if case .episode(let show, let episode) = hit { return episode.station(show: show) }
            return nil
        }
    }

    private var stationStations: [Station] {
        model.hits.compactMap { hit in
            if case .station(let station) = hit { return station }
            return nil
        }
    }

    private func searchRow(
        art: Station, title: String, subtitle: String, action: @escaping () -> Void
    ) -> some View {
        ListRow(
            onClick: action,
            leading: { StationArtView(station: art, size: 40, fallback: .glyph) },
            trailing: {
                CliampIcon(CliampIcons.caretRight, size: 9, tint: palette.inkFaint)
            },
            verticalPadding: 9,
            rail: player.station?.url == art.url,
            railOffset: cliampGutter
        ) {
            Text(title)
                .cliampText(CliampType.rowPrimary)
                .foregroundStyle(player.station?.url == art.url ? palette.accent : palette.ink)
                .lineLimit(1)
            Text(subtitle)
                .cliampText(CliampType.rowSecondary)
                .foregroundStyle(palette.inkTertiary)
                .lineLimit(1)
        }
    }

    private func play(_ station: Station, from queue: [Station]) {
        player.play(station, from: queue)
    }
}
