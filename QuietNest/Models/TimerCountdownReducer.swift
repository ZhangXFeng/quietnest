import Foundation

struct TimerCountdownState {
    var timerActive: Bool
    var remainingSeconds: Int
    var fadeStarted: Bool
}

enum TimerCountdownEvent: Equatable {
    case startFadeOut(durationSec: Int)
    case finishAndPause
}

enum TimerCountdownReducer {
    static let fadeDurationSec = 300

    static func tick(_ state: TimerCountdownState) -> (TimerCountdownState, [TimerCountdownEvent]) {
        guard state.timerActive else { return (state, []) }
        guard state.remainingSeconds > 0 else {
            return (
                TimerCountdownState(
                    timerActive: false,
                    remainingSeconds: 0,
                    fadeStarted: state.fadeStarted
                ),
                []
            )
        }

        var next = state
        var events: [TimerCountdownEvent] = []
        next.remainingSeconds -= 1

        if !next.fadeStarted, next.remainingSeconds > 0, next.remainingSeconds <= fadeDurationSec {
            next.fadeStarted = true
            events.append(.startFadeOut(durationSec: fadeDurationSec))
        }

        if next.remainingSeconds <= 0 {
            next.timerActive = false
            next.remainingSeconds = 0
            events.append(.finishAndPause)
        }

        return (next, events)
    }
}
