import XCTest
@testable import ZipClip

final class SpeedPlanTests: XCTestCase {
    func testEightySecondsUsesUniformRate() {
        let plan = SpeedPlan.make(sourceDuration: 80, targetDuration: 60)
        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.segments[0].rate, 80.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(plan.segments[0].startFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.segments[0].endFraction, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.outputDuration, 60, accuracy: 0.001)
        XCTAssertTrue(plan.summary.contains("1.33"))
    }

    func testSegmentedEndsUseFiveSecondsAtOnePointTwo() {
        let source = 180.0
        let target = 60.0
        let plan = SpeedPlan.make(sourceDuration: source, targetDuration: target)
        XCTAssertEqual(plan.segments.count, 3)
        XCTAssertEqual(plan.segments[0].rate, 1.2, accuracy: 0.0001)
        XCTAssertEqual(plan.segments[2].rate, 1.2, accuracy: 0.0001)
        XCTAssertEqual(plan.segments[0].endFraction, 5.0 / source, accuracy: 0.0001)
        XCTAssertEqual(plan.segments[1].startFraction, 5.0 / source, accuracy: 0.0001)
        XCTAssertEqual(plan.segments[1].endFraction, 1 - 5.0 / source, accuracy: 0.0001)
        XCTAssertEqual(plan.segments[2].startFraction, 1 - 5.0 / source, accuracy: 0.0001)

        let endsOutput = 10.0 / 1.2
        let middleRate = (source - 10) / (target - endsOutput)
        XCTAssertEqual(plan.segments[1].rate, middleRate, accuracy: 0.0001)
        XCTAssertGreaterThan(plan.segments[1].rate, 1.5)

        let total = plan.segments.reduce(0) { $0 + $1.outputDuration(sourceDuration: source) }
        XCTAssertEqual(total, target, accuracy: 0.01)
    }

    func testShortClipDoesNotSpeedUp() {
        let plan = SpeedPlan.make(sourceDuration: 40, targetDuration: 60)
        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.segments[0].rate, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.outputDuration, 40, accuracy: 0.001)
    }

    func testTooShortForEndsFallsBackToUniform() {
        let plan = SpeedPlan.make(sourceDuration: 8, targetDuration: 4)
        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.segments[0].rate, 2, accuracy: 0.0001)
    }

    func testTargetShorterThanEndsUsesUniform() {
        let plan = SpeedPlan.make(sourceDuration: 120, targetDuration: 5)
        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.segments[0].rate, 120.0 / 5.0, accuracy: 0.001)
    }
}
