import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum ClipError: Error, Equatable {
    case noVideoTrack
    case readerFailed
    case writerFailed
    case cancelled
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

final class VideoProcessor: @unchecked Sendable {
    func export(
        asset: AVAsset,
        sourceBytes: Int64?,
        targetDuration: TimeInterval?,
        targetBytes: Int64?,
        to outputURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let flag = CancelFlag()
        try await withTaskCancellationHandler {
            try await exportUnchecked(
                asset: asset,
                sourceBytes: sourceBytes,
                targetDuration: targetDuration,
                targetBytes: targetBytes,
                to: outputURL,
                cancel: flag,
                onProgress: onProgress
            )
        } onCancel: {
            flag.cancel()
        }
    }

    private func exportUnchecked(
        asset: AVAsset,
        sourceBytes: Int64?,
        targetDuration: TimeInterval?,
        targetBytes: Int64?,
        to outputURL: URL,
        cancel: CancelFlag,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        if cancel.isCancelled { throw ClipError.cancelled }
        let built = try await build(asset: asset, sourceBytes: sourceBytes, targetDuration: targetDuration, targetBytes: targetBytes)
        if cancel.isCancelled { throw ClipError.cancelled }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        do {
            try await write(built, to: outputURL, codec: .hevc, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, cancel: cancel, onProgress: onProgress)
        } catch ClipError.cancelled {
            throw ClipError.cancelled
        } catch {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            if cancel.isCancelled { throw ClipError.cancelled }
            try await write(built, to: outputURL, codec: .h264, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, cancel: cancel, onProgress: onProgress)
        }
    }

    private struct BuiltClip {
        var composition: AVMutableComposition
        var videoComposition: AVMutableVideoComposition
        var videoTrack: AVMutableCompositionTrack
        var audioTrack: AVMutableCompositionTrack?
        var encode: EncodePlan
        var outputDuration: Double
    }

    private func build(
        asset: AVAsset,
        sourceBytes: Int64?,
        targetDuration: TimeInterval?,
        targetBytes: Int64?
    ) async throws -> BuiltClip {
        let duration = try await asset.load(.duration)
        let sourceSeconds = duration.seconds
        guard sourceSeconds > 0 else { throw ClipError.noVideoTrack }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideo = videoTracks.first else { throw ClipError.noVideoTrack }
        let naturalSize = try await sourceVideo.load(.naturalSize)
        let preferred = try await sourceVideo.load(.preferredTransform)
        let nominalRate = try await sourceVideo.load(.nominalFrameRate)
        let dataRate = try await sourceVideo.load(.estimatedDataRate)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let sourceAudio = audioTracks.first

        let speedTarget = targetDuration ?? sourceSeconds
        let plan = SpeedPlan.make(sourceDuration: sourceSeconds, targetDuration: speedTarget)
        let composition = AVMutableComposition()
        guard let destVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ClipError.noVideoTrack
        }
        let sourceRange = CMTimeRange(start: .zero, duration: duration)
        try destVideo.insertTimeRange(sourceRange, of: sourceVideo, at: .zero)
        destVideo.preferredTransform = .identity
        apply(plan, to: destVideo, sourceDuration: duration)

        var destAudio: AVMutableCompositionTrack?
        if let sourceAudio {
            destAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            if let destAudio {
                try destAudio.insertTimeRange(sourceRange, of: sourceAudio, at: .zero)
                apply(plan, to: destAudio, sourceDuration: duration)
            }
        }

        let display = displaySize(naturalSize: naturalSize, transform: preferred)
        let outputSeconds = max(composition.duration.seconds, 0.1)
        let knownBytes = sourceBytes ?? estimatedBytes(asset: asset, duration: sourceSeconds, dataRate: dataRate)
        let sourceBits: Double
        if dataRate > 1 {
            sourceBits = Double(dataRate)
        } else if knownBytes > 0 {
            sourceBits = Double(knownBytes) * 8 / sourceSeconds
        } else {
            sourceBits = 0
        }
        let encode = EncodePlan.make(
            displayWidth: display.width,
            displayHeight: display.height,
            sourceFrameRate: Double(nominalRate),
            outputDuration: outputSeconds,
            sourceBitsPerSecond: sourceBits,
            targetBytes: targetBytes
        )

        let renderSize = CGSize(width: encode.width, height: encode.height)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(encode.frameRate))
        videoComposition.renderScale = 1
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: destVideo)
        layer.setTransform(renderTransform(naturalSize: naturalSize, preferred: preferred, renderSize: renderSize), at: .zero)
        instruction.layerInstructions = [layer]
        videoComposition.instructions = [instruction]

        return BuiltClip(
            composition: composition,
            videoComposition: videoComposition,
            videoTrack: destVideo,
            audioTrack: destAudio,
            encode: encode,
            outputDuration: outputSeconds
        )
    }

    /// Scales later ranges first so earlier source times stay put.
    private func apply(_ plan: SpeedPlan, to track: AVMutableCompositionTrack, sourceDuration: CMTime) {
        let changed = plan.segments.contains { abs($0.rate - 1) > 0.0001 }
        guard changed else { return }
        let sourceSeconds = sourceDuration.seconds
        guard sourceSeconds > 0 else { return }
        for segment in plan.segments.reversed() {
            guard segment.rate > 0 else { continue }
            let start = CMTime(seconds: sourceSeconds * segment.startFraction, preferredTimescale: 600)
            let end = CMTime(seconds: sourceSeconds * segment.endFraction, preferredTimescale: 600)
            let range = CMTimeRange(start: start, end: end)
            guard range.duration.seconds > 0.001 else { continue }
            let output = CMTime(seconds: range.duration.seconds / segment.rate, preferredTimescale: 600)
            track.scaleTimeRange(range, toDuration: output)
        }
    }

    private func estimatedBytes(asset: AVAsset, duration: Double, dataRate: Float) -> Int64 {
        if let urlAsset = asset as? AVURLAsset,
           let size = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)[.size] as? NSNumber,
           size.int64Value > 0 {
            return size.int64Value
        }
        guard dataRate > 0, duration > 0 else { return 0 }
        return Int64(Double(dataRate) * duration / 8)
    }

    private func displaySize(naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }

    private func renderTransform(naturalSize: CGSize, preferred: CGAffineTransform, renderSize: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let display = CGSize(width: abs(rect.width), height: abs(rect.height))
        guard display.width > 1, display.height > 1 else { return .identity }
        var normalized = preferred
        normalized.tx -= rect.origin.x
        normalized.ty -= rect.origin.y
        let scale = min(renderSize.width / display.width, renderSize.height / display.height)
        let scaled = CGSize(width: display.width * scale, height: display.height * scale)
        let dx = (renderSize.width - scaled.width) / 2
        let dy = (renderSize.height - scaled.height) / 2
        return normalized
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    private func write(
        _ built: BuiltClip,
        to outputURL: URL,
        codec: AVVideoCodecType,
        pixelFormat: OSType,
        cancel: CancelFlag,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: built.composition)
        } catch {
            throw ClipError.readerFailed
        }
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [built.videoTrack],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        )
        videoOutput.videoComposition = built.videoComposition
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else { throw ClipError.readerFailed }
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderTrackOutput?
        if let audioTrack = built.audioTrack {
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            output.alwaysCopiesSampleData = false
            // Keep the original pitch while speeding up. Varispeed raises pitch
            // with rate and makes voices sound thin compared with most editors.
            output.audioTimePitchAlgorithm = .spectral
            if reader.canAdd(output) {
                reader.add(output)
                audioOutput = output
            }
        }
        guard reader.startReading() else {
            if pixelFormat != kCVPixelFormatType_32BGRA {
                try await write(built, to: outputURL, codec: codec, pixelFormat: kCVPixelFormatType_32BGRA, cancel: cancel, onProgress: onProgress)
                return
            }
            throw ClipError.readerFailed
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw ClipError.writerFailed
        }
        writer.shouldOptimizeForNetworkUse = false
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(built.encode, codec: codec))
        videoInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput) else { throw ClipError.writerFailed }
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: built.encode.audioBitrate,
            ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }

        guard writer.startWriting() else {
            reader.cancelReading()
            throw writer.error ?? ClipError.writerFailed
        }
        writer.startSession(atSourceTime: .zero)

        let outputDuration = max(built.outputDuration, 0.001)
        let gate = ProgressGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = ResumeBox(continuation)
            let remaining = Remaining(count: audioInput == nil ? 1 : 2)
            let videoQueue = DispatchQueue(label: "zipclip.video", qos: .userInitiated)
            let audioQueue = DispatchQueue(label: "zipclip.audio", qos: .userInitiated)

            func finishInput(_ error: Error?) {
                let (done, failure) = remaining.mark(error)
                guard done else { return }
                if let failure {
                    reader.cancelReading()
                    writer.cancelWriting()
                    box.resume(throwing: failure)
                } else {
                    writer.finishWriting {
                        if writer.status == .completed {
                            box.resume()
                        } else {
                            box.resume(throwing: writer.error ?? ClipError.writerFailed)
                        }
                    }
                }
            }

            videoInput.requestMediaDataWhenReady(on: videoQueue) {
                while videoInput.isReadyForMoreMediaData {
                    if cancel.isCancelled {
                        videoInput.markAsFinished()
                        finishInput(ClipError.cancelled)
                        return
                    }
                    var sample: CMSampleBuffer?
                    autoreleasepool {
                        sample = videoOutput.copyNextSampleBuffer()
                    }
                    if let sample {
                        if !videoInput.append(sample) {
                            videoInput.markAsFinished()
                            finishInput(writer.error ?? ClipError.writerFailed)
                            return
                        }
                        let fraction = min(1, CMSampleBufferGetPresentationTimeStamp(sample).seconds / outputDuration)
                        if gate.allow(force: fraction >= 0.999) {
                            onProgress(fraction)
                        }
                    } else {
                        videoInput.markAsFinished()
                        let failure: Error? = reader.status == .failed ? (reader.error ?? ClipError.readerFailed) : nil
                        finishInput(failure)
                        return
                    }
                }
            }

            if let audioInput, let audioOutput {
                audioInput.requestMediaDataWhenReady(on: audioQueue) {
                    while audioInput.isReadyForMoreMediaData {
                        if cancel.isCancelled {
                            audioInput.markAsFinished()
                            finishInput(ClipError.cancelled)
                            return
                        }
                        var sample: CMSampleBuffer?
                        autoreleasepool {
                            sample = audioOutput.copyNextSampleBuffer()
                        }
                        if let sample {
                            if !audioInput.append(sample) {
                                audioInput.markAsFinished()
                                finishInput(writer.error ?? ClipError.writerFailed)
                                return
                            }
                        } else {
                            audioInput.markAsFinished()
                            let failure: Error? = reader.status == .failed ? (reader.error ?? ClipError.readerFailed) : nil
                            finishInput(failure)
                            return
                        }
                    }
                }
            }
        }
        onProgress(1)
    }

    private func videoSettings(_ encode: EncodePlan, codec: AVVideoCodecType) -> [String: Any] {
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: encode.videoBitrate,
            AVVideoExpectedSourceFrameRateKey: encode.frameRate,
            AVVideoMaxKeyFrameIntervalKey: encode.frameRate * 2,
        ]
        if codec == .h264 {
            compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: encode.width,
            AVVideoHeightKey: encode.height,
            AVVideoCompressionPropertiesKey: compression,
        ]
    }
}

private final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = CFAbsoluteTimeGetCurrent() - 1

    func allow(force: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        if !force && now - last < 0.1 { return false }
        last = now
        return true
    }
}

private final class Remaining: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int
    private var failure: Error?

    init(count: Int) {
        self.count = count
    }

    func mark(_ error: Error?) -> (done: Bool, failure: Error?) {
        lock.lock()
        defer { lock.unlock() }
        if failure == nil { failure = error }
        count -= 1
        return (count == 0, failure)
    }
}

private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}
