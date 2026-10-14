import Foundation

struct EncodePlan: Equatable {
    var width: Int
    var height: Int
    var frameRate: Int
    var videoBitrate: Int
    var audioBitrate: Int

    static let audioBitrateDefault = 96_000
    static let minimumVideoBitrate = 150_000

    /// Fits the picture to a 1920 long edge and at most 30 fps, then lowers
    /// the long edge when a size budget would make the bitrate too thin.
    /// When `targetBytes` is nil, keep a quality-preserving rate from the source.
    static func make(
        displayWidth: Double,
        displayHeight: Double,
        sourceFrameRate: Double,
        outputDuration: Double,
        sourceBitsPerSecond: Double,
        targetBytes: Int64?
    ) -> EncodePlan {
        let measuredRate = sourceFrameRate > 1 ? Int(sourceFrameRate.rounded()) : 30
        let frameRate = min(30, max(1, measuredRate))
        let duration = max(outputDuration, 0.1)
        let audioBitrate = audioBitrateDefault

        let videoBitrate: Int
        if let targetBytes {
            let budgetBits = Double(targetBytes) * 8 - Double(audioBitrate) * duration
            let cap = max(minimumVideoBitrate, Int(budgetBits / duration))
            if sourceBitsPerSecond > 1 {
                videoBitrate = min(cap, max(minimumVideoBitrate, Int(sourceBitsPerSecond)))
            } else {
                videoBitrate = cap
            }
        } else if sourceBitsPerSecond > 1 {
            videoBitrate = max(minimumVideoBitrate, Int(sourceBitsPerSecond))
        } else {
            videoBitrate = 4_000_000
        }

        var size = fitted(width: displayWidth, height: displayHeight, longEdge: 1920)
        if targetBytes != nil, bitsPerPixel(bitrate: videoBitrate, size: size, frameRate: frameRate) < 0.07 {
            for edge in [1280.0, 960.0] {
                let candidate = fitted(width: displayWidth, height: displayHeight, longEdge: edge)
                if min(candidate.width, candidate.height) < 480 { break }
                size = candidate
                if bitsPerPixel(bitrate: videoBitrate, size: size, frameRate: frameRate) >= 0.07 { break }
            }
        }

        return EncodePlan(
            width: size.width,
            height: size.height,
            frameRate: frameRate == 0 ? 30 : frameRate,
            videoBitrate: videoBitrate,
            audioBitrate: audioBitrate
        )
    }

    private static func bitsPerPixel(bitrate: Int, size: (width: Int, height: Int), frameRate: Int) -> Double {
        let pixels = Double(size.width * size.height * max(frameRate, 1))
        guard pixels > 0 else { return 0 }
        return Double(bitrate) / pixels
    }

    private static func fitted(width: Double, height: Double, longEdge: Double) -> (width: Int, height: Int) {
        let safeWidth = max(width, 2)
        let safeHeight = max(height, 2)
        let scale = min(1, longEdge / max(safeWidth, safeHeight))
        return (even(safeWidth * scale), even(safeHeight * scale))
    }

    private static func even(_ value: Double) -> Int {
        let floored = Int(value.rounded(.down))
        let even = floored - (floored % 2)
        return max(2, even)
    }
}
