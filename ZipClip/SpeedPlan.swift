import Foundation

struct SpeedSegment: Equatable {
    /// Start position as a fraction of the source duration, from 0 to 1.
    var startFraction: Double
    /// End position as a fraction of the source duration, from 0 to 1.
    var endFraction: Double
    /// Playback rate. 1 keeps the original speed.
    var rate: Double

    func outputDuration(sourceDuration: Double) -> Double {
        let span = max(0, endFraction - startFraction) * sourceDuration
        guard rate > 0 else { return span }
        return span / rate
    }
}

struct SpeedPlan: Equatable {
    static let endSeconds = 5.0
    static let endRate = 1.2
    static let uniformThreshold = 1.5

    var segments: [SpeedSegment]
    /// Duration after the speed change. Stays at the source duration when no change is needed.
    var outputDuration: Double

    var summary: String {
        let changed = segments.contains { abs($0.rate - 1) > 0.001 }
        guard changed else { return L10n.speedSizeOnly }
        if segments.count == 1 {
            return L10n.speedUniform(segments[0].rate)
        }
        return L10n.speedSegmented(segments[1].rate)
    }

    /// Builds the speed change for a hard duration limit.
    ///
    /// When the required rate is at most 1.5, the whole clip uses that rate.
    /// Above 1.5, the first and last 5 seconds stay at 1.2x and the middle rate
    /// is solved so the result matches the limit. Short clips that cannot spare
    /// both ends, or targets already used up by those ends, fall back to a
    /// uniform rate.
    static func make(sourceDuration: Double, targetDuration: Double) -> SpeedPlan {
        guard sourceDuration > 0 else {
            return SpeedPlan(segments: [SpeedSegment(startFraction: 0, endFraction: 1, rate: 1)], outputDuration: 0)
        }
        guard targetDuration > 0, sourceDuration > targetDuration else {
            return SpeedPlan(
                segments: [SpeedSegment(startFraction: 0, endFraction: 1, rate: 1)],
                outputDuration: sourceDuration
            )
        }

        let ratio = sourceDuration / targetDuration
        let endSpan = endSeconds
        let endsSource = endSpan * 2
        let endsOutput = endsSource / endRate
        let middleSource = sourceDuration - endsSource
        let middleBudget = targetDuration - endsOutput

        let canSegment =
            ratio > uniformThreshold
            && middleSource > 0.05
            && middleBudget > 0.05

        if !canSegment {
            return SpeedPlan(
                segments: [SpeedSegment(startFraction: 0, endFraction: 1, rate: ratio)],
                outputDuration: targetDuration
            )
        }

        let middleRate = middleSource / middleBudget
        let startFraction = endSpan / sourceDuration
        let endFraction = 1 - startFraction
        return SpeedPlan(
            segments: [
                SpeedSegment(startFraction: 0, endFraction: startFraction, rate: endRate),
                SpeedSegment(startFraction: startFraction, endFraction: endFraction, rate: middleRate),
                SpeedSegment(startFraction: endFraction, endFraction: 1, rate: endRate),
            ],
            outputDuration: targetDuration
        )
    }
}
