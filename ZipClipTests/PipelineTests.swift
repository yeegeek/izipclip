import AVFoundation
import CoreVideo
import XCTest
@testable import ZipClip

final class PipelineTests: XCTestCase {
    func testExportShortensAOneSecondClip() async throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-source.mp4")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-out.mp4")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try writeSample(to: sourceURL, seconds: 1)

        let asset = AVURLAsset(url: sourceURL)
        let processor = VideoProcessor()
        try await processor.export(
            asset: asset,
            sourceBytes: nil,
            targetDuration: 0.5,
            targetBytes: Int64(400_000),
            to: outputURL
        ) { _ in }

        let values = try await AVURLAsset(url: outputURL).load(.duration, .tracks)
        XCTAssertEqual(values.1.isEmpty, false)
        XCTAssertEqual(values.0.seconds, 0.5, accuracy: 0.2)
        let size = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber
        XCTAssertGreaterThan(size?.int64Value ?? 0, 0)
    }

    private func writeSample(to url: URL, seconds: Int) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 800_000],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 240,
            ]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? ClipError.writerFailed
        }
        writer.startSession(atSourceTime: .zero)
        let fps = 30
        for frame in 0..<(seconds * fps) {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let buffer = solidBuffer(frame: frame) else { continue }
            let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps))
            adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        let done = expectation(description: "sample")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 10)
        if writer.status != .completed {
            throw writer.error ?? ClipError.writerFailed
        }
    }

    private func solidBuffer(frame: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            320,
            240,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let shade = UInt8((frame * 8) % 255)
        for y in 0..<240 {
            let row = base.advanced(by: y * bytesPerRow)
            for x in 0..<320 {
                let pixel = row.advanced(by: x * 4)
                pixel.storeBytes(of: shade, as: UInt8.self)
                pixel.advanced(by: 1).storeBytes(of: UInt8(80), as: UInt8.self)
                pixel.advanced(by: 2).storeBytes(of: UInt8(40), as: UInt8.self)
                pixel.advanced(by: 3).storeBytes(of: UInt8(255), as: UInt8.self)
            }
        }
        return buffer
    }
}
