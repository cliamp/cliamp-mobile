import AVFoundation
import CliampCore
import MediaPlayer
import UIKit

/// The outside-of-app half of playback: lock screen and Control Center
/// metadata, remote commands, audio interruptions and route changes.
/// `RadioPlayer` owns exactly one instance, so every system control drives the
/// same stream the app does - and a second player can never exist.
@MainActor
final class SystemPlayback {
    private weak var player: RadioPlayer?
    private var artworkTask: Task<Void, Never>?

    init(player: RadioPlayer) {
        self.player = player
        configureCommands()
        observeAudioSession()
    }

    /// Mirrors the player onto the lock screen. Called after every state
    /// change the phone can observe: station, ICY title, play/pause.
    func refresh() {
        guard let player else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard let station = player.station else {
            center.nowPlayingInfo = nil
            refreshCommands()
            return
        }
        var info = center.nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = station.name
        info[MPMediaItemPropertyArtist] = player.streamTitle.isEmpty
            ? station.sourceLine : player.streamTitle
        info[MPMediaItemPropertyAlbumTitle] = station.meta
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.playing ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        center.nowPlayingInfo = info
        refreshCommands()
        refreshArtwork(for: station)
    }

    private func refreshCommands() {
        guard let player else { return }
        let center = MPRemoteCommandCenter.shared()
        // Availability follows intent, not audibility: during a buffer stall
        // the lock screen must still offer Pause.
        center.playCommand.isEnabled = player.station != nil && !player.wantsToPlay
        center.pauseCommand.isEnabled = player.wantsToPlay
        center.nextTrackCommand.isEnabled = player.hasNext
        center.previousTrackCommand.isEnabled = player.hasPrev
    }

    private func refreshArtwork(for station: Station) {
        artworkTask?.cancel()
        artworkTask = nil
        if let cached = StationArtwork.shared.cached(for: station) {
            applyArtwork(cached, station: station)
            return
        }
        artworkTask = Task { [weak self] in
            let image = await StationArtwork.shared.image(for: station)
            guard !Task.isCancelled, let self else { return }
            self.applyArtwork(image, station: station)
        }
    }

    private func applyArtwork(_ image: UIImage?, station: Station) {
        guard let player, player.station?.url == station.url else { return }
        let center = MPNowPlayingInfoCenter.default()
        var info = center.nowPlayingInfo ?? [:]
        if let image {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        } else {
            info.removeValue(forKey: MPMediaItemPropertyArtwork)
        }
        center.nowPlayingInfo = info
    }

    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.goNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.goPrevious() }
            return .success
        }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(rawType: rawType, rawOptions: rawOptions)
            }
        }
        center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self?.handleRouteChange(rawReason: rawReason)
            }
        }
    }

    private func handleInterruption(rawType: UInt?, rawOptions: UInt?) {
        guard let player, let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }
        switch type {
        case .began:
            player.pauseFromInterruption()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0)
            if player.takeInterruptionResumeWanted(), options.contains(.shouldResume) {
                player.resume()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(rawReason: UInt?) {
        guard let rawReason,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
        else { return }
        // Unplugging headphones pauses, the same as Android's
        // setHandleAudioBecomingNoisy(true).
        if reason == .oldDeviceUnavailable {
            player?.pause()
        }
    }
}
