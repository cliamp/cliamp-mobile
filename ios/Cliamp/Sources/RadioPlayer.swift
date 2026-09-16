import AVFoundation
import CliampCore
import Foundation
import Observation
import os

/// One AVPlayer owns the session, so nothing can ever produce two streams.
/// The engine is deliberately small until FND-03 picks the final audio stack;
/// what it proves today is live radio with a real transport.
@MainActor
@Observable
final class RadioPlayer {
    private let player = AVPlayer()
    private let errorLog = Logger(subsystem: "stream.cliamp.mobile", category: "player")
    private let icy = IcyMetadataReader()
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var tap: SpectrumTap?
    private var ticker: Timer?
    private var sessionConfigured = false
    private var navigator = RadioNavigator()
    private var navTask: Task<Void, Never>?

    /// The latest 64-band FFT frame from the audio thread, empty when nothing
    /// is flowing. The meters read it; nothing else should.
    let spectrum = SpectrumStore()

    private(set) var station: Station?
    private(set) var streamTitle = ""
    private(set) var bufferedSeconds = 0
    private(set) var playing = false
    private(set) var buffering = false
    private(set) var error: String?
    private(set) var elapsedMs: Int64 = 0

    /// Called on every user-initiated play so history and the last station
    /// reach persistence at one choke point (RAD-12).
    var onRecordPlay: ((Station) -> Void)?

    /// Where prev/next walk when no explicit source list exists: recent
    /// history, or favourites when history is empty. Read live so a new
    /// favourite is navigable without a copy going stale.
    var fallbackProvider: (() -> [Station])?

    private(set) var hasPrev = false
    private(set) var hasNext = false

    init() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                self?.apply(status)
            }
        }
    }

    func play(_ station: Station) {
        navigator.cancelPending()
        navTask?.cancel()
        navTask = nil
        begin(station)
    }

    private func begin(_ station: Station) {
        configureSessionIfNeeded()
        self.station = station
        error = nil
        elapsedMs = 0
        bufferedSeconds = 0
        streamTitle = ""
        icy.stop()
        spectrum.clear()
        guard let url = URL(string: station.url) else {
            error = "couldn't play that stream"
            updateNavigationAvailability()
            return
        }
        onRecordPlay?(station)
        navigator.recordPlay(station)
        updateNavigationAvailability()
        let item = AVPlayerItem(url: url)
        // A post-effects tap gives the meters the PCM that is actually
        // playing, for the real FFT. If the tap cannot attach, the meter
        // falls back to its idle stagger and audio is unaffected.
        #if DEBUG
        let tapDisabled = ProcessInfo.processInfo.arguments.contains("-cliamp-no-tap")
        #else
        let tapDisabled = false
        #endif
        let spectrumTap = SpectrumTap(store: spectrum)
        if !tapDisabled, let processor = spectrumTap.makeProcessingTap() {
            let mix = AVMutableAudioMix()
            let parameters = AVMutableAudioMixInputParameters()
            parameters.audioTapProcessor = processor
            mix.inputParameters = [parameters]
            item.audioMix = mix
            tap = spectrumTap
        }
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            let error = item.error as NSError?
            Task { @MainActor [weak self] in
                guard let self, status == .failed else { return }
                self.errorLog.error(
                    "item failed code=\(error?.code ?? 0, privacy: .public) domain=\(error?.domain ?? "-", privacy: .public) underlying=\(String(describing: error?.userInfo[NSUnderlyingErrorKey]), privacy: .public)"
                )
                self.error = message ?? "couldn't play that stream"
                self.playing = false
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
        icy.start(url: url) { [weak self] title in
            Task { @MainActor [weak self] in
                self?.streamTitle = title
            }
        }
    }

    /// Shows the last station without making a sound, matching the Android
    /// service restoring `last_station` for the mini player while auto-resume
    /// is off. A station already on screen wins.
    func restore(_ station: Station) {
        guard self.station == nil else { return }
        self.station = station
        updateNavigationAvailability()
    }

    /// Steps forward: the redo tail first, then the fallback ring. An isolated
    /// tap lands immediately; a burst settles on the final target.
    func goNext() {
        let stations = fallback()
        guard !stations.isEmpty else { return }
        switch navigator.next(stations: stations, current: station, nowMs: nowMs()) {
        case .play(let target): begin(target)
        case .schedule: schedulePending()
        case .ignore: break
        }
    }

    /// Steps back through what was heard this session, then the ring.
    func goPrevious() {
        let stations = fallback()
        guard !stations.isEmpty else { return }
        switch navigator.previous(stations: stations, current: station, nowMs: nowMs()) {
        case .play(let target): begin(target)
        case .schedule: schedulePending()
        case .ignore: break
        }
    }

    /// The fallback list changed (a new favourite, a play recorded): recompute
    /// whether the transport keys can go anywhere.
    func refreshNavigation() {
        updateNavigationAvailability()
    }

    private func schedulePending() {
        navTask?.cancel()
        navTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(RadioNavigator.debounceWindowMs)))
            guard !Task.isCancelled, let self else { return }
            self.navTask = nil
            guard let target = self.navigator.takePending(stations: self.fallback()) else { return }
            self.begin(target)
        }
    }

    private func updateNavigationAvailability() {
        let ring = fallback().count > 1
        hasPrev = ring || navigator.canGoBack
        hasNext = ring || navigator.canGoForward
    }

    private func fallback() -> [Station] {
        fallbackProvider?() ?? []
    }

    /// Monotonic milliseconds, the iOS counterpart of Android's uptimeMillis.
    private func nowMs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    func toggle() {
        guard station != nil else { return }
        if playing {
            player.pause()
            icy.stop()
        } else {
            error = nil
            player.play()
            resumeMetadata()
        }
    }

    private func resumeMetadata() {
        guard let station, let url = URL(string: station.url) else { return }
        icy.start(url: url) { [weak self] title in
            Task { @MainActor [weak self] in
                self?.streamTitle = title
            }
        }
    }

    private func apply(_ status: AVPlayer.TimeControlStatus) {
        buffering = status == .waitingToPlayAtSpecifiedRate
        playing = status == .playing
        updateTicker()
    }

    private func updateTicker() {
        if playing, ticker == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let item = self.player.currentItem else { return }
                    let seconds = CMTimeGetSeconds(item.currentTime())
                    if seconds.isFinite, seconds >= 0 {
                        self.elapsedMs = Int64(seconds * 1000)
                    }
                    let ahead = item.loadedTimeRanges
                        .map { CMTimeGetSeconds($0.timeRangeValue.end) }
                        .max() ?? 0
                    if ahead.isFinite, seconds.isFinite {
                        self.bufferedSeconds = max(0, Int(ahead - seconds))
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        } else if !playing, let ticker {
            ticker.invalidate()
            self.ticker = nil
        }
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        sessionConfigured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }
}
