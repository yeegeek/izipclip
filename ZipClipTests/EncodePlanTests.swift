import XCTest
@testable import ZipClip

final class EncodePlanTests: XCTestCase {
    func testFourKDropsToAFasterSize() {
        let target = 25 * 1024 * 1024
        let plan = EncodePlan.make(
            displayWidth: 3840,
            displayHeight: 2160,
            sourceFrameRate: 60,
            outputDuration: 60,
            sourceBitsPerSecond: 20_000_000,
            targetBytes: Int64(target)
        )
        XCTAssertLessThanOrEqual(max(plan.width, plan.height), 1280)
        XCTAssertEqual(plan.frameRate, 30)
        XCTAssertEqual(plan.width % 2, 0)
        XCTAssertEqual(plan.height % 2, 0)
        let bits = Double(plan.videoBitrate) * 60 + Double(plan.audioBitrate) * 60
        XCTAssertLessThanOrEqual(bits / 8, Double(target) + 1)
    }

    func testPortraitKeepsShape() {
        let plan = EncodePlan.make(
            displayWidth: 1080,
            displayHeight: 1920,
            sourceFrameRate: 30,
            outputDuration: 30,
            sourceBitsPerSecond: 8_000_000,
            targetBytes: 50 * 1024 * 1024
        )
        XCTAssertGreaterThan(plan.height, plan.width)
        XCTAssertLessThanOrEqual(plan.height, 1920)
        XCTAssertEqual(plan.frameRate, 30)
    }

    func testNoSizeBudgetKeepsSourceBitrate() {
        let plan = EncodePlan.make(
            displayWidth: 1920,
            displayHeight: 1080,
            sourceFrameRate: 30,
            outputDuration: 60,
            sourceBitsPerSecond: 8_000_000,
            targetBytes: nil
        )
        XCTAssertEqual(plan.videoBitrate, 8_000_000)
        XCTAssertEqual(max(plan.width, plan.height), 1920)
    }
}
