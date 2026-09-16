import CliampCore
import CliampDesign
import SwiftUI

/// One show: header, subscribe toggle, and its episodes newest-first with
/// download controls. Ported from Android's `PodcastShowScreen`.
struct PodcastShowScreen: View {
    @Environment(\.cliampPalette) private var palette
    let player: RadioPlayer
    let podcasts: PodcastsModel
    let downloads: DownloadManager
    let show: PodcastShow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topRow
            ScrollView {
                LazyVStack(spacing: 0) {
                    header
                    SectionLabel("episodes — \(podcasts.episodes.count)") { EmptyView() }
                    episodesSection
                    Spacer().frame(height: 20)
                }
            }
        }
        .background(palette.ground)
        .task { podcasts.openShow(show) }
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            BackChevron { dismiss() }
            Spacer()
            CliampIcon(CliampIcons.download, size: 16, tint: palette.inkSecondary)
                .frame(width: 32, height: 32)
                .opacity(0)
            CliampIcon(CliampIcons.lines, size: 16, tint: palette.accent)
                .frame(width: 32, height: 32)
                .microPress { podcasts.refreshShow() }
                .accessibilityLabel("refresh feed")
            SubscribeStar(
                subscribed: podcasts.isSubscribed(feedUrl: show.feedUrl)
            ) {
                podcasts.toggleSubscription(show)
            }
        }
        .padding(.horizontal, cliampGutter)
        .frame(height: 48)
    }

    private var currentShow: PodcastShow {
        podcasts.show ?? show
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                StationArtSquare(station: currentShow.artStation)
                    .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentShow.title)
                        .cliampText(CliampType.trackTitleSmall)
                        .foregroundStyle(palette.ink)
                        .lineLimit(3)
                    Text(currentShow.meta.isEmpty ? "podcast" : currentShow.meta)
                        .cliampText(CliampType.rowSecondary)
                        .foregroundStyle(palette.inkTertiary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            if !currentShow.description.isEmpty, currentShow.description != currentShow.title {
                Text(currentShow.description)
                    .cliampText(CliampType.rowSecondary)
                    .foregroundStyle(palette.inkSecondary)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, cliampGutter)
        .padding(.top, 4)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var episodesSection: some View {
        if podcasts.showLoading, podcasts.episodes.isEmpty {
            EmptyNote("reading the feed…")
        } else if let error = podcasts.showError, podcasts.episodes.isEmpty {
            RetryNote("couldn't read the feed", prominent: true) {
                _ = error
                podcasts.refreshShow()
            }
        } else if podcasts.episodes.isEmpty {
            EmptyNote("no episodes in this feed")
        } else {
            ForEach(podcasts.episodes, id: \.guid) { episode in
                EpisodeRow(
                    episode: episode,
                    show: currentShow,
                    active: player.station?.url == episode.audioUrl,
                    playing: player.playing,
                    progress: podcasts.progressEntry(for: episode.audioUrl),
                    downloadState: downloads.state(for: episode.audioUrl),
                    downloaded: downloads.isDownloaded(url: episode.audioUrl),
                    onPlay: { play(episode) },
                    onToggleDownload: { toggleDownload(episode) },
                    onRemoveDownload: { downloads.remove(url: episode.audioUrl) },
                    onMarkPlayed: { podcasts.markCompleted(episode.station(show: currentShow)) },
                    onClearProgress: { podcasts.clearProgress(episode.station(show: currentShow)) }
                )
            }
        }
    }

    /// Episodes play in the displayed show order; the whole list is the
    /// source, so Next walks to the following episode.
    private func play(_ episode: PodcastEpisode) {
        let stations = podcasts.episodes.map { $0.station(show: currentShow) }
        guard let station = stations.first(where: { $0.url == episode.audioUrl }) else { return }
        player.play(station, from: stations)
    }

    private func toggleDownload(_ episode: PodcastEpisode) {
        let url = episode.audioUrl
        if downloads.isDownloaded(url: url) {
            downloads.remove(url: url)
            return
        }
        if case .active = downloads.state(for: url) {
            downloads.cancel(url: url)
            return
        }
        downloads.download(episode.station(show: currentShow))
    }
}

/// One episode row: title, date/duration, progress, and the fetch control.
private struct EpisodeRow: View {
    @Environment(\.cliampPalette) private var palette
    let episode: PodcastEpisode
    let show: PodcastShow
    let active: Bool
    let playing: Bool
    let progress: EpisodeProgress?
    let downloadState: DownloadState?
    let downloaded: Bool
    let onPlay: () -> Void
    let onToggleDownload: () -> Void
    let onRemoveDownload: () -> Void
    let onMarkPlayed: () -> Void
    let onClearProgress: () -> Void

    var body: some View {
        ListRow(
            onClick: onPlay,
            leading: {
                StationArtView(station: episode.station(show: show), size: 40, fallback: .glyph)
                    .overlay {
                        if active {
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
                    }
            },
            trailing: {
                HStack(spacing: 10) {
                    if let progress, progress.completed {
                        Text("done")
                            .cliampText(CliampType.meta)
                            .foregroundStyle(palette.accent)
                    }
                    downloadControl
                    Menu {
                        Button("play", action: onPlay)
                        Button("mark played", action: onMarkPlayed)
                        if progress != nil {
                            Button("clear progress", action: onClearProgress)
                        }
                        if downloaded {
                            Button("remove download", role: .destructive, action: onRemoveDownload)
                        }
                    } label: {
                        CliampIcon(CliampIcons.more, size: 16, tint: palette.ink)
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                }
            },
            verticalPadding: 9,
            rail: active,
            railOffset: cliampGutter
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.title)
                    .cliampText(CliampType.rowPrimary)
                    .foregroundStyle(active ? palette.accent : palette.ink)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(episode.listMeta)
                        .cliampText(CliampType.rowSecondary)
                        .foregroundStyle(palette.inkTertiary)
                        .lineLimit(1)
                    if let progress, !progress.completed, progress.fraction > 0 {
                        Text("· \(Int(progress.fraction * 100))%")
                            .cliampText(CliampType.rowSecondary)
                            .foregroundStyle(palette.accent)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var downloadControl: some View {
        switch downloadState {
        case .active(let fraction, let read, let total):
            Button(action: onToggleDownload) {
                Text(progressLabel(fraction: fraction, read: read, total: total))
                    .cliampText(CliampType.meta)
                    .foregroundStyle(palette.accent)
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("cancel download")
        case .failed:
            CliampIcon(CliampIcons.download, size: 16, tint: palette.destructiveInk)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggleDownload)
                .accessibilityLabel("retry download")
        case nil:
            CliampIcon(
                downloaded ? CliampIcons.check : CliampIcons.download,
                size: 16,
                tint: downloaded ? palette.accent : palette.inkSecondary
            )
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleDownload)
            .accessibilityLabel(downloaded ? "remove download" : "download")
        }
    }

    private func progressLabel(fraction: Double, read: Int64, total: Int64) -> String {
        if fraction < 0 {
            return downloadSizeLabel(read)
        }
        return "\(Int(fraction * 100))%"
    }
}
