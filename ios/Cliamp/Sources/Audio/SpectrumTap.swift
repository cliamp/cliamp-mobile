import Accelerate
import AVFoundation
import CliampCore
import Foundation
import Synchronization
import os

/// Real playback FFT from AVPlayer's decoded output. A post-effects
/// `MTAudioProcessingTap` hands over the PCM that is actually playing, vDSP
/// folds it into 64 log-spaced bands, and `SpectrumStore` publishes the most
/// recent frame for the meters. No synthetic animation is ever published.
final class SpectrumTap {
    static let bandCount = 64
    private static let log2n = vDSP_Length(10)
    private static let fftSize = 1 << 10

    private let store: SpectrumStore
    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let window: [Float]
    private var ring: [Float]
    private var writeIndex = 0
    private var samplesSinceTransform = 0
    private var splitReal: [Float]
    private var splitImag: [Float]
    private var magnitudes: [Float]
    private var windowed: [Float]
    private var format: AudioStreamBasicDescription?
    private let logger = Logger(subsystem: "stream.cliamp.mobile", category: "spectrum")

    init(store: SpectrumStore) {
        self.store = store
        fft = vDSP.FFT(log2n: Self.log2n, radix: .radix2, ofType: DSPSplitComplex.self)
        var hann = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_DENORM))
        window = hann
        ring = [Float](repeating: 0, count: Self.fftSize)
        splitReal = [Float](repeating: 0, count: Self.fftSize / 2)
        splitImag = [Float](repeating: 0, count: Self.fftSize / 2)
        magnitudes = [Float](repeating: 0, count: Self.fftSize / 2)
        windowed = [Float](repeating: 0, count: Self.fftSize)
    }

    func makeProcessingTap() -> MTAudioProcessingTap? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passUnretained(self).toOpaque(),
            init: spectrumTapInit,
            finalize: spectrumTapFinalize,
            prepare: spectrumTapPrepare,
            unprepare: spectrumTapUnprepare,
            process: spectrumTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard status == noErr else {
            logger.error("tap create failed: \(status, privacy: .public)")
            return nil
        }
        return tap
    }

    fileprivate func prepare(_ format: UnsafePointer<AudioStreamBasicDescription>) {
        self.format = format.pointee
        let asbd = format.pointee
        logger.info(
            "tap prepared: \(asbd.mSampleRate, privacy: .public) Hz, \(asbd.mChannelsPerFrame, privacy: .public) ch, flags \(asbd.mFormatFlags, privacy: .public)"
        )
    }

    fileprivate func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard let asbd = format, frames > 0 else { return }
        guard asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return }
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let interleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let firstBuffer = buffers.first, let firstData = firstBuffer.mData else { return }
        let firstCount = min(frames, Int(firstBuffer.mDataByteSize) / MemoryLayout<Float>.size)
        guard firstCount > 0 else { return }
        let first = firstData.assumingMemoryBound(to: Float.self)
        // Average the two front channels so panning never moves the meter.
        let second: UnsafeMutablePointer<Float>? = if !interleaved, buffers.count > 1,
            let data = buffers[1].mData
        {
            data.assumingMemoryBound(to: Float.self)
        } else {
            nil
        }

        for frame in 0..<firstCount {
            let value: Float
            if interleaved {
                value = first[frame * channels]
            } else if let second {
                value = (first[frame] + second[frame]) * 0.5
            } else {
                value = first[frame]
            }
            ring[writeIndex] = value
            writeIndex = (writeIndex + 1) % Self.fftSize
            samplesSinceTransform += 1

            if samplesSinceTransform >= Self.fftSize / 2 {
                samplesSinceTransform = 0
                transform()
            }
        }
    }

    private func transform() {
        for i in 0..<Self.fftSize {
            windowed[i] = ring[(writeIndex + i) % Self.fftSize] * window[i]
        }
        windowed.withUnsafeBufferPointer { samples in
            splitReal.withUnsafeMutableBufferPointer { real in
                splitImag.withUnsafeMutableBufferPointer { imag in
                    magnitudes.withUnsafeMutableBufferPointer { magnitude in
                        var split = DSPSplitComplex(
                            realp: real.baseAddress!,
                            imagp: imag.baseAddress!
                        )
                        samples.baseAddress!.withMemoryRebound(
                            to: DSPComplex.self, capacity: Self.fftSize / 2
                        ) { complex in
                            vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(Self.fftSize / 2))
                        }
                        fft?.forward(input: split, output: &split)
                        vDSP_zvabs(
                            &split, 1, magnitude.baseAddress!, 1,
                            vDSP_Length(Self.fftSize / 2)
                        )
                    }
                }
            }
        }
        // A Hann windowed full-scale sine peaks at N/4, so 4/N references it.
        let bands = SpectrumBands.fold(
            magnitudes: magnitudes,
            bands: Self.bandCount,
            scale: 4 / Float(Self.fftSize),
            dynamicRangeDb: 54
        )
        store.publish(bands)
    }
}

/// Handoff from the audio thread to the meters. The critical section is one
/// array copy; if DEC-01 ever replaces AVPlayer this becomes a lock-free
/// triple buffer.
final class SpectrumStore: Sendable {
    private let state = Mutex<[Float]>([])

    func publish(_ bands: [Float]) {
        state.withLock { $0 = bands }
    }

    func latest() -> [Float]? {
        state.withLock { $0 }
    }

    func clear() {
        state.withLock { $0 = [] }
    }
}

private let spectrumTapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, storageOut in
    storageOut.pointee = clientInfo
}

private let spectrumTapFinalize: MTAudioProcessingTapFinalizeCallback = { _ in }

private let spectrumTapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, format in
    let storage = MTAudioProcessingTapGetStorage(tap)
    let processor = Unmanaged<SpectrumTap>.fromOpaque(storage).takeUnretainedValue()
    processor.prepare(format)
}

private let spectrumTapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

private let spectrumTapProcess: MTAudioProcessingTapProcessCallback = {
    tap, numberFrames, _, bufferList, framesOut, flagsOut in
    let status = MTAudioProcessingTapGetSourceAudio(
        tap, numberFrames, bufferList, flagsOut, nil, framesOut
    )
    guard status == noErr else { return }
    let storage = MTAudioProcessingTapGetStorage(tap)
    let processor = Unmanaged<SpectrumTap>.fromOpaque(storage).takeUnretainedValue()
    processor.process(bufferList, frames: Int(framesOut.pointee))
}
