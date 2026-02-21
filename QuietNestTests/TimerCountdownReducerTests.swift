import XCTest
@testable import QuietNest

final class TimerCountdownReducerTests: XCTestCase {

    func testTickDoesNothingWhenInactive() {
        let state = TimerCountdownState(timerActive: false, remainingSeconds: 500, fadeStarted: false)
        let (next, events) = TimerCountdownReducer.tick(state)

        XCTAssertEqual(next.timerActive, false)
        XCTAssertEqual(next.remainingSeconds, 500)
        XCTAssertEqual(next.fadeStarted, false)
        XCTAssertTrue(events.isEmpty)
    }

    func testTickStartsFadeWhenCrossingIntoLastFiveMinutes() {
        let state = TimerCountdownState(timerActive: true, remainingSeconds: 301, fadeStarted: false)
        let (next, events) = TimerCountdownReducer.tick(state)

        XCTAssertEqual(next.remainingSeconds, 300)
        XCTAssertEqual(next.fadeStarted, true)
        XCTAssertEqual(events, [.startFadeOut(durationSec: 300)])
    }

    func testTickStartsFadeInsideLastFiveMinutesIfNotStarted() {
        let state = TimerCountdownState(timerActive: true, remainingSeconds: 300, fadeStarted: false)
        let (next, events) = TimerCountdownReducer.tick(state)

        XCTAssertEqual(next.remainingSeconds, 299)
        XCTAssertEqual(next.fadeStarted, true)
        XCTAssertEqual(events, [.startFadeOut(durationSec: 300)])
    }

    func testTickFinishesAtZeroAndPauses() {
        let state = TimerCountdownState(timerActive: true, remainingSeconds: 1, fadeStarted: true)
        let (next, events) = TimerCountdownReducer.tick(state)

        XCTAssertEqual(next.timerActive, false)
        XCTAssertEqual(next.remainingSeconds, 0)
        XCTAssertEqual(events, [.finishAndPause])
    }
}
