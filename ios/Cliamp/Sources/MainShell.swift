import CliampCore
import CliampDesign
import SwiftUI
import UIKit

/// The permanent chrome: mini player plus tabs, never removed for the whole
/// session, with the landscape rail replacing the bottom bar.
struct MainShell: View {
    @Environment(\.cliampPalette) private var palette
    @Binding var tab: AppTab
    let player: RadioPlayer
    let app: AppState
    let onOpenSettings: () -> Void
    let onOpenPlayer: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let rail = proxy.size.width > proxy.size.height
            let bottomInset = proxy.safeAreaInsets.bottom
            if rail {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        content
                        MiniPlayerBar(player: player, app: app, onOpen: onOpenPlayer)
                    }
                    CliampTabRail(current: tab, onSelect: select)
                }
            } else {
                VStack(spacing: 0) {
                    content
                    MiniPlayerBar(player: player, app: app, onOpen: onOpenPlayer)
                    CliampTabBar(current: tab, onSelect: select, bottomInset: bottomInset)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .stations:
            StationsScreen(player: player, app: app, onOpenSettings: onOpenSettings)
        case .pods:
            PlaceholderTab(title: "Podcasts")
        case .library:
            PlaceholderTab(title: "Library")
        }
    }

    private func select(_ tab: AppTab) {
        withAnimation(.easeOut(duration: 0.18)) {
            self.tab = tab
        }
    }
}

/// Fills the gap for the two tabs that arrive in phases 3 and 4.
private struct PlaceholderTab: View {
    @Environment(\.cliampPalette) private var palette
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            CliampHeader(title, onSettings: {})
            Spacer()
            Text("this tab lands in a later phase")
                .cliampText(CliampType.rowSecondary)
                .foregroundStyle(palette.inkFaint)
            Spacer()
        }
        .background(palette.ground)
    }
}

/// The lockscreen widget's in-app twin: art (or the meter), title, one transport.
struct MiniPlayerBar: View {
    @Environment(\.cliampPalette) private var palette
    let player: RadioPlayer
    let app: AppState
    let onOpen: () -> Void
    @State private var meter: MeterModel
    @State private var artImage: UIImage?

    init(player: RadioPlayer, app: AppState, onOpen: @escaping () -> Void) {
        self.player = player
        self.app = app
        self.onOpen = onOpen
        _meter = State(initialValue: MeterModel(preset: .mini, player: player))
    }

    var body: some View {
        VStack(spacing: 0) {
            HairlineDivider(region: true)
            HStack(spacing: 12) {
                art
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.station?.name ?? "nothing playing")
                        .cliampText(CliampType.rowPrimaryMedium)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Text(statusLine)
                        .cliampText(CliampType.rowSecondary)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    miniKey(CliampIcons.prev, label: "previous", enabled: player.hasPrev) {
                        player.goPrevious()
                    }
                    Button {
                        player.toggle()
                    } label: {
                        CliampIcon(
                            player.playing ? CliampIcons.pause : CliampIcons.playTab,
                            size: player.playing ? 13 : 15,
                            tint: palette.dark ? palette.onAccent : palette.ground
                        )
                        .frame(width: 38, height: 38)
                        .background(palette.dark ? palette.accent : palette.ink)
                        .clipShape(RoundedRectangle(cornerRadius: CliampShape.medium))
                    }
                    .buttonStyle(MicroPressStyle())
                    .disabled(player.station == nil)
                    miniKey(CliampIcons.next, label: "next", enabled: player.hasNext) {
                        player.goNext()
                    }
                }
            }
            .padding(.horizontal, cliampGutter)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .background(palette.panel)
        .onAppear {
            if app.visualizer != "off" { meter.start() }
        }
        .onDisappear { meter.stop() }
        .onChange(of: app.visualizer) { _, value in
            if value == "off" { meter.stop() } else { meter.start() }
        }
    }

    private var art: some View {
        Group {
            if let artImage {
                Image(uiImage: artImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: CliampShape.medium))
            } else if player.station != nil, app.visualizer != "off" {
                BrickMeter(levels: meter.levels, peaks: meter.peaks, preset: .mini)
                    .frame(width: 40, height: MeterPreset.mini.height)
            } else {
                ArtPlate()
                    .overlay(
                        CliampIcon(CliampIcons.stationsTab, size: 20, tint: palette.accent)
                    )
                    .frame(width: 40, height: 40)
            }
        }
        .task(id: player.station?.id) {
            artImage = nil
            guard let station = player.station else { return }
            let loaded: UIImage?
            if let cached = StationArtwork.shared.cachedSmall(for: station) {
                loaded = cached
            } else {
                loaded = await StationArtwork.shared.smallImage(for: station)
            }
            guard !Task.isCancelled else { return }
            artImage = loaded
        }
    }

    private var statusLine: String {
        guard let station = player.station else { return "pick a station to start" }
        if player.reconnecting { return "reconnecting…" }
        if let error = player.error { return error }
        if player.buffering { return "buffering…" }
        if !player.streamTitle.isEmpty { return player.streamTitle }
        return station.sourceLine
    }

    private var statusColor: Color {
        player.reconnecting || player.buffering ? palette.amber : palette.inkTertiary
    }

    private func miniKey(
        _ icon: CliampVector, label: String, enabled: Bool, action: @escaping () -> Void
    ) -> some View {
        CliampIcon(icon, width: 14, height: 11, tint: enabled ? palette.ink : palette.inkFaint)
            .frame(width: 28, height: 28)
            .background(palette.keyFace)
            .clipShape(RoundedRectangle(cornerRadius: CliampShape.small))
            .overlay(
                RoundedRectangle(cornerRadius: CliampShape.small)
                    .stroke(palette.keyBorder, lineWidth: 1)
            )
            .microPress(enabled: enabled, action: action)
    }
}

struct CliampTabBar: View {
    @Environment(\.cliampPalette) private var palette
    let current: AppTab
    let onSelect: (AppTab) -> Void
    let bottomInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            HairlineDivider(region: true)
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    tabItem(tab).frame(maxWidth: .infinity)
                }
            }
        }
        .background(palette.ground)
    }

    private func tabItem(_ tab: AppTab) -> some View {
        let active = tab == current
        let tint = active ? palette.accent : palette.inkTertiary
        return VStack(spacing: 6) {
            CliampIcon(tab.icon, size: 17, tint: tint)
                .frame(height: 17)
            Text(tab.rawValue)
                .cliampText(CliampType.tabLabel)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.top, 13)
        .padding(.bottom, max(30, bottomInset + 8))
        .overlay(alignment: .top) {
            if active {
                Rectangle()
                    .fill(palette.accent)
                    .frame(height: 2)
                    .offset(y: -1)
            }
        }
        .microPress { onSelect(tab) }
    }
}

struct CliampTabRail: View {
    @Environment(\.cliampPalette) private var palette
    let current: AppTab
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(palette.hairlineRegion)
                .frame(width: 1)
            VStack(spacing: 8) {
                ForEach(AppTab.allCases) { tab in
                    railItem(tab).frame(maxHeight: .infinity)
                }
            }
            .frame(width: cliampTabRailWidth - 1)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: .infinity)
        .background(palette.ground)
    }

    private func railItem(_ tab: AppTab) -> some View {
        let active = tab == current
        let tint = active ? palette.accent : palette.inkTertiary
        return VStack(spacing: 5) {
            Spacer(minLength: 0)
            CliampIcon(tab.icon, size: 17, tint: tint)
                .frame(height: 17)
            Text(tab.rawValue)
                .cliampText(CliampType.tabLabel)
                .foregroundStyle(tint)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(width: 70)
        .overlay(alignment: .trailing) {
            if active {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CliampShape.medium))
        .microPress { onSelect(tab) }
    }
}
