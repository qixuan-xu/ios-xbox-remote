import XCTest
@testable import XboxRemote

final class CaptionTests: XCTestCase {

    func testFinalizeAfterPause() {
        let start = Date(timeIntervalSince1970: 0)
        let last = start.addingTimeInterval(2)
        XCTAssertFalse(CaptionSegmenter.shouldFinalize(text: "hello", lastUpdate: last, taskStart: start, now: last.addingTimeInterval(0.5)))
        XCTAssertTrue(CaptionSegmenter.shouldFinalize(text: "hello", lastUpdate: last, taskStart: start, now: last.addingTimeInterval(1.3)))
        // 没有文字时，停顿不算一句
        XCTAssertFalse(CaptionSegmenter.shouldFinalize(text: "  ", lastUpdate: last, taskStart: start, now: last.addingTimeInterval(5)))
    }

    func testFinalizeAfterMaxTaskDuration() {
        let start = Date(timeIntervalSince1970: 0)
        let now = start.addingTimeInterval(51)
        XCTAssertTrue(CaptionSegmenter.shouldFinalize(text: "", lastUpdate: now, taskStart: start, now: now))
    }

    func testTrimKeepsLatest() {
        let lines = (0..<5).map { CaptionLine(original: "\($0)", translated: nil, finishedAt: Date()) }
        XCTAssertEqual(CaptionSegmenter.trimmed(lines).map(\.original), ["2", "3", "4"])
    }

    func testPacingBuffers() {
        XCTAssertEqual(VideoPacing.smooth.bufferMilliseconds, 67)
        XCTAssertEqual(VideoPacing.balanced.bufferMilliseconds, 34)
        XCTAssertEqual(VideoPacing.lowLatency.bufferMilliseconds, 0)
        XCTAssertFalse(CaptionLanguage.chinese.needsTranslation)
        XCTAssertTrue(CaptionLanguage.english.needsTranslation)
    }
}
