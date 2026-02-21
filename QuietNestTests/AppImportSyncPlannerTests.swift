import XCTest
@testable import QuietNest

final class AppImportSyncPlannerTests: XCTestCase {

    func testMakeDecisionWhenNoChanges() {
        let tracks = [Track(emoji: "🌧️", name: "雨声", volume: 0.7)]
        let decision = AppImportSyncPlanner.makeDecision(
            currentScene: "雨夜书房",
            currentTracks: tracks,
            restoredScene: "雨夜书房",
            restoredTracks: tracks
        )
        XCTAssertEqual(decision, AppImportSyncDecision(shouldApplyPreset: false, shouldSetScene: false))
    }

    func testMakeDecisionWhenSceneChanged() {
        let decision = AppImportSyncPlanner.makeDecision(
            currentScene: "雨夜书房",
            currentTracks: [Track(emoji: "🌧️", name: "雨声", volume: 0.7)],
            restoredScene: "森林书桌",
            restoredTracks: [Track(emoji: "🐦", name: "鸟鸣", volume: 0.5)]
        )
        XCTAssertEqual(decision, AppImportSyncDecision(shouldApplyPreset: true, shouldSetScene: true))
    }

    func testMakeDecisionWhenOnlyTracksChanged() {
        let decision = AppImportSyncPlanner.makeDecision(
            currentScene: "雨夜书房",
            currentTracks: [Track(emoji: "🌧️", name: "雨声", volume: 0.7)],
            restoredScene: "雨夜书房",
            restoredTracks: [Track(emoji: "🌧️", name: "雨声", volume: 0.9)]
        )
        XCTAssertEqual(decision, AppImportSyncDecision(shouldApplyPreset: true, shouldSetScene: false))
    }

    func testMakeDecisionForceApply() {
        let decision = AppImportSyncPlanner.makeDecision(
            currentScene: "",
            currentTracks: [],
            restoredScene: "雨夜书房",
            restoredTracks: [Track(emoji: "🌧️", name: "雨声", volume: 0.7)],
            forceApply: true
        )
        XCTAssertEqual(decision, AppImportSyncDecision(shouldApplyPreset: true, shouldSetScene: true))
    }

    func testMakeDecisionIgnoresTrimAndTinyVolumeDelta() {
        let decision = AppImportSyncPlanner.makeDecision(
            currentScene: "雨夜书房",
            currentTracks: [Track(emoji: "🌧️", name: " 雨声 ", volume: 0.7004)],
            restoredScene: "雨夜书房",
            restoredTracks: [Track(emoji: "🌧️", name: "雨声", volume: 0.7009)]
        )
        XCTAssertEqual(decision, AppImportSyncDecision(shouldApplyPreset: false, shouldSetScene: false))
    }

    func testMakeDecisionDetectsTrackOrderChange() {
        let current = [
            Track(emoji: "🌧️", name: "雨声", volume: 0.7),
            Track(emoji: "🔥", name: "篝火", volume: 0.4),
        ]
        let restored = [
            Track(emoji: "🔥", name: "篝火", volume: 0.4),
            Track(emoji: "🌧️", name: "雨声", volume: 0.7),
        ]
        let decision = AppImportSyncPlanner.makeDecision(
            currentScene: "雨夜书房",
            currentTracks: current,
            restoredScene: "雨夜书房",
            restoredTracks: restored
        )
        XCTAssertEqual(decision, AppImportSyncDecision(shouldApplyPreset: true, shouldSetScene: false))
    }
}
