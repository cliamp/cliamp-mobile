import AVFoundation
import CliampCore
import Foundation
import Network
import Observation
import os

/// One AVPlayer owns the session, so nothing can ever produce two streams.
/// The engine is deliberately small until FND-03 picks the final audio stack;
/// what it proves today is live radio with a real transport, a reconnect
/// ladder and the lock screen.
///
/// A process-wide singleton: SwiftUI can rebuild the root view as often as it
/// likes without standing up a second AVPlayer, remote-command set, watchdog
/// or network monitor.
@MainActor
@Observable
final class RadioPlayer {
    static let shared = RadioPlayer()

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
    private var system: SystemPlayback?
    private var policy = ReconnectPolicy()
    private var retryTask: Task<Void, Never>?
    private var watchdog: Timer?
    private var bufferingSinceMs: Int64?
    private var pathMonitor: NWPathMonitor?
    /// The session's active list: what a tap from a screen set, or the frozen
    /// fallback the first navigation promoted. Empty until then.
    private var source: [Station] = []
    /// True while navigation is walking the launch fallback as a ring.
    private var ringFallback = false
    /// Set when an audio interruption pauses something worth resuming.
    private var resumeAfterInterruption = false
    /// The URL actually handed to AVPlayer: a playlist link resolves to this
    /// before playback and retries reuse it instead of re-fetching.
    private var streamURL: URL?
    /// Distinguishes newer plays from playlist resolutions that finish late.
    private var playGeneration = 0

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
    /// Amber recovery state: the first attempt starts at 1.
    private(set) var reconnecting = false
    private(set) var reconnectAttempt = 0
    /// The user's intent, the iOS counterpart of Android's `playWhenReady`:
    /// true through buffering and failures until pause. The transport glyphs
    /// follow this, not audibility.
    private(set) var wantsToPlay = false

    /// Called on every user-initiated play so history and the last station
    /// reach persistence at one choke point (RAD-12).
    var onRecordPlay: ((Station) -> Void)?

    /// Where prev/next walk before an explicit source exists: recent history,
    /// or favourites when history is empty.
    var fallbackProvider: (() -> [Station])?

    private(set) var hasPrev = false
    private(set) var hasNext = false

    private init() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                self?.apply(status)
            }
        }
        system = SystemPlayback(player: self)
        startWatchdog()
        startNetworkMonitor()
    }

    /// A play tapped on a screen hands navigation to that screen's list, the
    /// same source identity Android's `play(station, from)` establishes. A tap
    /// of something already in the active list keeps the list (and its order).
    func play(_ station: Station, from list: [Station] = []) {
        navigator.cancelPending()
        navTask?.cancel()
        navTask = nil
        if !list.isEmpty {
            source = list
            ringFallback = false
        } else if !source.contains(where: { $0.url == station.url }) {
            source = [station]
            ringFallback = false
        }
        begin(station)
    }

    private func begin(_ station: Station) {
        configureSessionIfNeeded()
        cancelRecovery()
        self.station = station
        error = nil
        elapsedMs = 0
        bufferedSeconds = 0
        streamTitle = ""
        wantsToPlay = true
        resumeAfterInterruption = false
        guard let url = URL(string: station.url) else {
            error = "couldn't play that stream"
            updateNavigationAvailability()
            system?.refresh()
            return
        }
        onRecordPlay?(station)
        navigator.recordPlay(station)
        updateNavigationAvailability()
        system?.refresh()
        playGeneration += 1
        streamURL = nil
        resolveStream(station: station, url: url, generation: playGeneration)
    }

    /// Directory entries sometimes point at an .m3u/.pls file rather than the
    /// stream; resolve one hop off the main actor, then play. HLS and direct
    /// URLs pass through untouched. While it resolves, the player reports
    /// buffering so the transport is honest about the wait.
    private func resolveStream(station: Station, url: URL, generation: Int) {
        buffering = true
        Task { [weak self] in
            let resolved = await StreamResolver.resolve(url.absoluteString)
            guard !Task.isCancelled, let self, generation == self.playGeneration,
                  let target = URL(string: resolved)
            else { return }
            self.buffering = false
            self.streamURL = target
            self.startStream(station: station, url: target)
        }
    }

    /// Builds a fresh item for [station] and plays it: the one path that ever
    /// touches AVPlayer, used by explicit plays, navigation and reconnects.
    private func startStream(station: Station, url: URL) {
        icy.stop()
        spectrum.clear()
        // A replacement stream gets a fresh stall deadline; if the previous
        // status was buffering, no status change will re-arm it.
        bufferingSinceMs = wantsToPlay ? nowMs() : nil
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
            let identity = ObjectIdentifier(item)
            Task { @MainActor [weak self] in
                guard let self, status == .failed, let error,
                      let current = self.player.currentItem,
                      ObjectIdentifier(current) == identity
                else { return }
                self.errorLog.error(
                    "item failed code=\(error.code, privacy: .public) domain=\(error.domain, privacy: .public) underlying=\(String(describing: error.userInfo[NSUnderlyingErrorKey]), privacy: .public)"
                )
                self.handleStreamFailure(error, message: message)
            }
        }
        player.replaceCurrentItem(with: item)
        // A stream resolved after the user already paused loads silently.
        if wantsToPlay {
            player.play()
        }
        icy.start(url: url) { [weak self] title in
            Task { @MainActor [weak self] in
                self?.streamTitle = title
                self?.system?.refresh()
            }
        }
    }

    /// A failed item either enters the backoff ladder or surfaces a stable
    /// error: malformed containers and unsupported codecs are not retried.
    private func handleStreamFailure(_ failure: NSError, message: String?) {
        if wantsToPlay, ReconnectPolicy.isRecoverable(failure) {
            scheduleRetry(reason: "error \(failure.code)")
            return
        }
        error = message ?? "couldn't play that stream"
        playing = false
        cancelRecovery()
        system?.refresh()
    }

    /// Shows the last station without making a sound, matching the Android
    /// service restoring `last_station` for the mini player while auto-resume
    /// is off. A station already on screen wins.
    func restore(_ station: Station) {
        guard self.station == nil else { return }
        self.station = station
        updateNavigationAvailability()
    }

    /// Steps forward: the redo tail first when walking the fallback, then the
    /// walked list. An isolated tap lands immediately; a burst settles on the
    /// final target.
    func goNext() {
        let walk = currentWalk()
        guard !walk.isEmpty else { return }
        let ring = isRing(walk)
        switch navigator.next(walk: walk, ring: ring, current: station, nowMs: nowMs()) {
        case .play(let target): commitNavigation(target, walk: walk)
        case .schedule: schedulePending()
        case .ignore: break
        }
    }

    /// Steps back through what was heard this session, then the walked list.
    func goPrevious() {
        let walk = currentWalk()
        guard !walk.isEmpty else { return }
        let ring = isRing(walk)
        switch navigator.previous(walk: walk, ring: ring, current: station, nowMs: nowMs()) {
        case .play(let target): commitNavigation(target, walk: walk)
        case .schedule: schedulePending()
        case .ignore: break
        }
    }

    /// The fallback list changed (a new favourite, a play recorded): recompute
    /// whether the transport keys can go anywhere.
    func refreshNavigation() {
        updateNavigationAvailability()
    }

    /// A navigation target is committed: the launch fallback is promoted into
    /// a frozen source the moment a step lands, exactly as Android's
    /// `startPlayback(..., preserveOrder = true)` does, so recency updates
    /// cannot reshuffle the walk under the next tap.
    private func commitNavigation(_ target: Station, walk: [Station]) {
        if source.isEmpty {
            source = walk
            ringFallback = true
        }
        begin(target)
    }

    private func schedulePending() {
        navTask?.cancel()
        navTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(RadioNavigator.debounceWindowMs)))
            guard !Task.isCancelled, let self else { return }
            self.navTask = nil
            let walk = self.currentWalk()
            guard let target = self.navigator.takePending(walk: walk) else { return }
            self.commitNavigation(target, walk: walk)
        }
    }

    private func currentWalk() -> [Station] {
        source.isEmpty ? fallback() : source
    }

    private func isRing(_ walk: [Station]) -> Bool {
        walk.count > 1 && (source.isEmpty || ringFallback)
    }

    private func updateNavigationAvailability() {
        let walk = currentWalk()
        let ring = isRing(walk)
        let index = station.flatMap { current in
            walk.firstIndex { $0.url == current.url }
        } ?? -1
        hasPrev = ring || navigator.canGoBack || (index > 0)
        hasNext = ring || (source.isEmpty && navigator.canGoForward)
            || (index >= 0 && index < walk.count - 1)
    }

    private func fallback() -> [Station] {
        fallbackProvider?() ?? []
    }

    /// Monotonic milliseconds, the iOS counterpart of Android's uptimeMillis.
    private func nowMs() -> Int64 {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    func toggle() {
        if wantsToPlay {
            pause()
        } else {
            resume()
        }
    }

    /// An explicit pause: the lock screen and the app's transport land here.
    func pause() {
        guard station != nil else { return }
        wantsToPlay = false
        resumeAfterInterruption = false
        player.pause()
        icy.stop()
        navigator.cancelPending()
        navTask?.cancel()
        navTask = nil
        cancelRecovery()
        system?.refresh()
    }

    /// Pauses for an audio interruption, remembering whether audio was wanted
    /// so it can come back when the interruption ends. Any explicit pause
    /// in the meantime clears that intent.
    func pauseFromInterruption() {
        let wasPlaying = wantsToPlay
        pause()
        resumeAfterInterruption = wasPlaying
    }

    /// Consumes the interruption-resume intent.
    func takeInterruptionResumeWanted() -> Bool {
        defer { resumeAfterInterruption = false }
        return resumeAfterInterruption
    }

    /// Resumes the loaded item, rebuilding it when the last one failed or the
    /// station only exists as restored cold-launch state.
    func resume() {
        guard station != nil else { return }
        error = nil
        wantsToPlay = true
        if let current = player.currentItem, current.status != .failed {
            player.play()
            resumeMetadata()
        } else if let station, let url = streamURL ?? URL(string: station.url) {
            configureSessionIfNeeded()
            startStream(station: station, url: url)
        }
        system?.refresh()
    }

    private func resumeMetadata() {
        guard let station, let url = URL(string: station.url) else { return }
        icy.start(url: url) { [weak self] title in
            Task { @MainActor [weak self] in
                self?.streamTitle = title
                self?.system?.refresh()
            }
        }
    }

    private func apply(_ status: AVPlayer.TimeControlStatus) {
        buffering = status == .waitingToPlayAtSpecifiedRate
        playing = status == .playing
        if buffering {
            if bufferingSinceMs == nil { bufferingSinceMs = nowMs() }
        } else {
            bufferingSinceMs = nil
        }
        if playing {
            // A stream that actually delivers audio resets the ladder and
            // disarms any retry that was still waiting.
            finishRecovery()
        }
        updateTicker()
        system?.refresh()
    }

    // MARK: reconnect

    /// Waits out the backoff ladder, then rebuilds the stream. Pausing,
    /// network return and a fresh play all cancel it first.
    private func scheduleRetry(reason: String) {
        guard retryTask == nil, station != nil else { return }
        let waitMs = policy.scheduleRetry()
        reconnectAttempt = policy.attempt
        reconnecting = true
        error = nil
        errorLog.info("reconnect #\(self.reconnectAttempt, privacy: .public) in \(waitMs)ms (\(reason, privacy: .public))")
        system?.refresh()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(waitMs))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            guard self.wantsToPlay, let station = self.station,
                  let url = self.streamURL ?? URL(string: station.url)
            else {
                self.finishRecovery()
                return
            }
            self.startStream(station: station, url: url)
        }
    }

    /// The 20-second stall watchdog: a stream that stops delivering without
    /// any error looks identical to a slow buffer until the timeout. A pending
    /// retry is already handling it; a replacement stream gets its own
    /// deadline from `startStream`.
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let interval = Double(ReconnectPolicy.watchdogIntervalMs) / 1000
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkStall()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func checkStall() {
        guard wantsToPlay, retryTask == nil, error == nil else { return }
        guard player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
              let since = bufferingSinceMs
        else { return }
        guard ReconnectPolicy.isStalled(bufferingSinceMs: since, nowMs: nowMs()) else { return }
        bufferingSinceMs = nil
        scheduleRetry(reason: "stalled with no error")
    }

    /// Coming back into signal retries now instead of waiting out the ladder.
    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                self?.networkReturned()
            }
        }
        monitor.start(queue: DispatchQueue(label: "stream.cliamp.mobile.network"))
        pathMonitor = monitor
    }

    private func networkReturned() {
        guard wantsToPlay, station != nil else { return }
        let failed = player.currentItem?.status == .failed
        guard reconnecting || failed else { return }
        retryTask?.cancel()
        retryTask = nil
        policy.reset()
        reconnectAttempt = 0
        reconnecting = false
        error = nil
        system?.refresh()
        guard let station, let url = streamURL ?? URL(string: station.url) else { return }
        startStream(station: station, url: url)
    }

    private func cancelRecovery() {
        retryTask?.cancel()
        retryTask = nil
        finishRecovery()
    }

    private func finishRecovery() {
        retryTask?.cancel()
        retryTask = nil
        policy.reset()
        reconnecting = false
        reconnectAttempt = 0
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
