import CliampCore
import CliampDesign
import SwiftUI

/// The full player. Portrait stacks art, meta, transport; a wide frame keeps
/// the same column centred at a readable width until the split layout lands.
struct NowPlayingScreen: View {
    @Environment(\.cliampPalette) private var palette
    let player: RadioPlayer
    let app: AppState
    let onClose: () -> Void
    @State private var meter: MeterModel

    init(player: RadioPlayer, app: AppState, onClose: @escaping () -> Void) {
        self.player = player
        self.app = app
        self.onClose = onClose
        _meter = State(initialValue: MeterModel(preset: .nowPlaying, player: player))
    }

    var body: some View {
        VStack(spacing: 0) {
            topRow
            GeometryReader { proxy in
                let artSide = min(proxy.size.width - cliampGutter * 2, 340)
                VStack(spacing: 0) {
                    Spacer(minLength: 8)
                    art(side: artSide)
                    Spacer().frame(height: 18)
                    statusStrip
                    Spacer().frame(height: 7)
                    meta
                    Spacer(minLength: 14)
                    transport
                    Spacer(minLength: 12)
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, cliampGutter)
            }
        }
        .background(palette.ground)
        .onAppear { meter.start() }
        .onDisappear { meter.stop() }
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            BackChevron(action: onClose)
            Spacer()
            HStack(spacing: 8) {
                CliampIcon(CliampIcons.queueTabLines, size: 14, tint: palette.accent)
                Text("UP NEXT")
                    .cliampText(CliampType.chip)
                    .foregroundStyle(palette.ink)
                Text("0")
                    .cliampText(CliampType.chip)
                    .foregroundStyle(palette.inkFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: CliampShape.small)
                    .stroke(palette.chipBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, cliampGutter)
        .frame(height: 48)
    }

    private func art(side: CGFloat) -> some View {
        ArtPlate(radius: CliampShape.medium)
            .overlay(
                CliampIcon(
                    player.station?.source == .cliamp ? CliampIcons.mark : CliampIcons.stationsTab,
                    size: side * 0.34,
                    tint: palette.accent
                )
            )
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity)
    }

    private var meta: some View {
        VStack(spacing: 7) {
            Text(player.station?.name ?? "pick a station")
                .cliampText(CliampType.trackTitle)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Text(player.error ?? statusFallback)
                .cliampText(CliampType.rowPrimary)
                .foregroundStyle(player.error != nil ? palette.destructiveInk : palette.inkSecondary)
                .lineLimit(1)
            Text(player.station?.sourceLine ?? "cliamp radio")
                .cliampText(CliampType.body)
                .foregroundStyle(palette.inkTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusFallback: String {
        guard let station = player.station else { return "nothing playing" }
        return station.tagList.prefix(3).joined(separator: " · ")
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            CliampIcon(CliampIcons.playTiny, width: 9, height: 10, tint: statusColor)
                .opacity(player.playing ? 1 : 0.6)
            Text(statusLabel)
                .cliampText(CliampType.nowPlayingLabel)
                .foregroundStyle(statusColor)
            Spacer()
            smallAction(CliampIcons.shuffle, label: "shuffle", enabled: false, tint: palette.inkSecondary) {}
            smallAction(CliampIcons.meterSmall, label: "scope and equaliser", enabled: false, tint: palette.inkSecondary) {}
            smallAction(
                app.isFavorite(player.station ?? placeholder) ? CliampIcons.starFilled : CliampIcons.star,
                label: "favourite",
                enabled: true,
                tint: app.isFavorite(player.station ?? placeholder) ? palette.accent : palette.inkTertiary
            ) {
                if let station = player.station { app.toggleFavorite(station) }
            }
        }
    }

    private var placeholder: Station {
        Station(id: "", name: "", url: "", source: .cliamp)
    }

    private var statusLabel: String {
        if player.error != nil { return "STREAM ERROR" }
        if player.buffering { return "BUFFERING" }
        if player.playing { return "ON AIR" }
        return player.station == nil ? "IDLE" : "PAUSED"
    }

    private var statusColor: Color {
        if player.error != nil { return palette.destructiveInk }
        if player.buffering { return palette.amber }
        return player.playing ? palette.accent : palette.inkSecondary
    }

    private func smallAction(
        _ icon: CliampVector, label: String, enabled: Bool, tint: Color, action: @escaping () -> Void
    ) -> some View {
        CliampIcon(icon, size: 16, tint: enabled ? tint : palette.inkFaint.opacity(0.5))
            .frame(width: 32, height: 32)
            .microPress(enabled: enabled, action: action)
            .accessibilityLabel(label)
    }

    private var transport: some View {
        VStack(spacing: 11) {
            if app.visualizer != "off" {
                BrickMeter(levels: meter.levels, peaks: meter.peaks, preset: .nowPlaying)
                    .frame(maxWidth: .infinity)
            }
            StreamingRule(streamingLabel, color: statusColor, dim: !player.playing && player.error == nil)
            HStack {
                Text(TimeFormat.clock(player.elapsedMs))
                    .cliampText(CliampType.time)
                    .foregroundStyle(palette.inkSecondary)
                Spacer()
                Text(player.playing ? "live" : "tap play")
                    .cliampText(CliampType.timeSmall)
                    .foregroundStyle(palette.inkFaint)
            }
            .padding(.bottom, 6)
            GeometryReader { proxy in
                let spacing = 9.0
                let available = max(0, proxy.size.width - spacing * 2)
                HStack(spacing: spacing) {
                    MechKey(enabled: false, action: {}) {
                        CliampIcon(CliampIcons.prev, width: 21, height: 17, tint: palette.ink)
                    }
                    .frame(width: available / 3.7)
                    MechKey(filled: true, height: 64, action: { player.toggle() }) {
                        CliampIcon(
                            player.playing ? CliampIcons.pause : CliampIcons.playTab,
                            width: player.playing ? 20 : 22,
                            height: player.playing ? 22 : 22,
                            tint: palette.onAccent
                        )
                    }
                    .frame(width: available * 1.7 / 3.7)
                    MechKey(enabled: false, action: {}) {
                        CliampIcon(CliampIcons.next, width: 21, height: 17, tint: palette.ink)
                    }
                    .frame(width: available / 3.7)
                }
            }
            .frame(height: 64)
        }
    }

    private var streamingLabel: String {
        if player.error != nil { return "stream error" }
        if player.buffering { return "buffering" }
        if player.playing { return "streaming" }
        return "paused"
    }
}
