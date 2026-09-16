import CliampCore
import CliampDesign
import SwiftUI

/// The first tab: cliamp's own channels, the custom slot, and - when the
/// directory lands - the community station list with its filters.
struct StationsScreen: View {
    @Environment(\.cliampPalette) private var palette
    let player: RadioPlayer
    let app: AppState
    let onOpenSettings: () -> Void

    @State private var filter: StationFilter = .all
    @State private var cliamp: [Station] = []
    @State private var gridMode = false

    enum StationFilter: String, CaseIterable, Identifiable {
        case all
        case cliamp
        case custom

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            CliampHeader("Stations", onSettings: onOpenSettings) {
                ForEach(StationFilter.allCases) { option in
                    Chip(option.rawValue, selected: filter == option) {
                        filter = option
                    }
                }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if filter == .all || filter == .cliamp {
                        cliampSection
                    }
                    if filter == .all || filter == .custom {
                        customSection
                    }
                    Spacer().frame(height: 20)
                }
            }
        }
        .background(palette.ground)
        .task {
            if cliamp.isEmpty {
                cliamp = await CliampRadio.fetchStations()
            }
        }
    }

    @ViewBuilder
    private var cliampSection: some View {
        SectionLabel("cliamp radio — \(cliamp.count)") {
            GridListToggle(gridMode: gridMode) { gridMode.toggle() }
        }
        if cliamp.isEmpty {
            EmptyNote("loading…")
        } else if gridMode {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 10)],
                spacing: 10
            ) {
                ForEach(cliamp) { station in
                    StationTile(
                        station: station,
                        active: player.station?.url == station.url,
                        playing: player.playing,
                        favorite: app.isFavorite(station),
                        action: { player.play(station) },
                        onToggleFavorite: { app.toggleFavorite(station) }
                    )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
        } else {
            ForEach(cliamp) { station in
                StationRow(
                    station: station,
                    active: player.station?.url == station.url,
                    playing: player.playing,
                    favorite: app.isFavorite(station),
                    action: { player.play(station) },
                    onToggleFavorite: { app.toggleFavorite(station) }
                )
            }
        }
    }

    @ViewBuilder
    private var customSection: some View {
        SectionLabel("custom — 0")
        EmptyNote("nothing here")
    }
}

private struct StationRow: View {
    @Environment(\.cliampPalette) private var palette
    let station: Station
    let active: Bool
    let playing: Bool
    let favorite: Bool
    let action: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        ListRow(
            onClick: action,
            leading: { StationThumb(station: station, active: active, playing: playing) },
            trailing: { FavoriteStar(favorite: favorite, action: onToggleFavorite) },
            verticalPadding: 9,
            gutter: 8,
            rail: active,
            railOffset: 14
        ) {
            Text(station.name)
                .cliampText(CliampType.rowPrimary)
                .foregroundStyle(active ? palette.accent : palette.ink)
                .lineLimit(1)
            Text(subtitle)
                .cliampText(CliampType.rowSecondary)
                .foregroundStyle(palette.inkTertiary)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if station.source == .cliamp { parts.append("cliamp radio") }
        if !station.meta.isEmpty { parts.append(station.meta) }
        parts.append(contentsOf: station.tagList.prefix(2))
        return parts.joined(separator: " · ")
    }
}

private struct StationTile: View {
    @Environment(\.cliampPalette) private var palette
    let station: Station
    let active: Bool
    let playing: Bool
    let favorite: Bool
    let action: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ArtPlate()
                .overlay(
                    CliampIcon(CliampIcons.stationsTab, size: 26, tint: palette.accent)
                )
                .overlay(alignment: .topTrailing) {
                    FavoriteStar(favorite: favorite, action: onToggleFavorite)
                        .padding(10)
                }
                .overlay {
                    if active {
                        RoundedRectangle(cornerRadius: CliampShape.medium)
                            .stroke(palette.accent, lineWidth: 2)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
            Text(station.name)
                .cliampText(CliampType.rowPrimaryMedium)
                .foregroundStyle(palette.ink)
                .lineLimit(2)
            Text("cliamp")
                .cliampText(CliampType.rowSecondary)
                .foregroundStyle(palette.inkTertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .clampTap(action: action)
    }
}

/// A station row's leading thumbnail: the broadcast mark on a themed plate,
/// which is all a cliamp channel has until a cover exists.
private struct StationThumb: View {
    @Environment(\.cliampPalette) private var palette
    let station: Station
    let active: Bool
    let playing: Bool

    var body: some View {
        if active {
            ZStack {
                RoundedRectangle(cornerRadius: CliampShape.small)
                    .stroke(palette.accent, lineWidth: 1)
                RoundedRectangle(cornerRadius: CliampShape.tiny)
                    .fill(palette.accent.opacity(0.92))
                    .overlay(
                        CliampIcon(
                            playing ? CliampIcons.pause : CliampIcons.playRow,
                            size: 9,
                            tint: palette.onAccent
                        )
                    )
                    .frame(width: 18, height: 18)
            }
            .frame(width: 40, height: 40)
        } else {
            GlyphPlate(CliampIcons.stationsTab, size: 40)
        }
    }
}

private struct FavoriteStar: View {
    @Environment(\.cliampPalette) private var palette
    let favorite: Bool
    let action: () -> Void

    var body: some View {
        CliampIcon(
            favorite ? CliampIcons.starFilled : CliampIcons.star,
            size: 15,
            tint: favorite ? palette.accent : palette.inkFaint
        )
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityLabel(favorite ? "remove favourite" : "favourite")
    }
}
