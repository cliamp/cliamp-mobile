import AVFoundation
import CliampCore
import Foundation
import Observation

/// One AVPlayer owns the session, so nothing can ever produce two streams.
/// The engine is deliberately small until FND-03 picks the final audio stack;
/// what it proves today is live radio with a real transport.
@MainActor
@Observable
final class RadioPlayer {
    private let player = AVPlayer()
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var tap: SpectrumTap?
    private var ticker: Timer?
    private var sessionConfigured = false

    /// The latest 64-band FFT frame from the audio thread, empty when nothing
    /// is flowing. The meters read it; nothing else should.
    let spectrum = SpectrumStore()

    private(set) var station: Station?
    private(set) var playing = false
    private(set) var buffering = false
    private(set) var error: String?
    private(set) var elapsedMs: Int64 = 0

    init() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in
                self?.apply(status)
            }
        }
    }

    func play(_ station: Station) {
        configureSessionIfNeeded()
        self.station = station
        error = nil
        elapsedMs = 0
        spectrum.clear()
        guard let url = URL(string: station.url) else {
            error = "couldn't play that stream"
            return
        }
        let item = AVPlayerItem(url: url)
        // A post-effects tap gives the meters the PCM that is actually
        // playing, for the real FFT. If the tap cannot attach, the meter
        // falls back to its idle stagger and audio is unaffected.
        let spectrumTap = SpectrumTap(store: spectrum)
        if let processor = spectrumTap.makeProcessingTap() {
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
            Task { @MainActor [weak self] in
                guard let self, status == .failed else { return }
                self.error = message ?? "couldn't play that stream"
                self.playing = false
            }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func toggle() {
        guard station != nil else { return }
        if playing {
            player.pause()
        } else {
            error = nil
            player.play()
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
