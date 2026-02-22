import XCTest
@testable import QuietNest

final class AppStateRestorePlannerTests: XCTestCase {

    func testRestoreUsesLastTracksWhenValid() throws {
        let presets = samplePresets()
        let tracks = [Track(emoji: "🌧️", name: "雨声", volume: 0.6)]
        let raw = try encodeTracks(tracks)

        let restored = AppStateRestorePlanner.restoreScene(
            lastTracksData: raw,
            lastPresetName: "雨夜书房",
            availablePresets: presets,
            defaultPresetName: "雨夜书房",
            fallbackTracks: []
        )

        XCTAssertEqual(restored.selectedPreset, "雨夜书房")
        XCTAssertEqual(restored.tracks.count, 1)
        XCTAssertEqual(restored.tracks[0].name, "雨声")
    }

    func testRestoreFallsBackWhenPresetMissingOrTracksInvalid() {
        let presets = samplePresets()
        let restored = AppStateRestorePlanner.restoreScene(
            lastTracksData: "not-json",
            lastPresetName: "不存在",
            availablePresets: presets,
            defaultPresetName: "雨夜书房",
            fallbackTracks: [Track(emoji: "🔥", name: "篝火", volume: 0.5)]
        )

        XCTAssertEqual(restored.selectedPreset, "雨夜书房")
        XCTAssertEqual(restored.tracks.count, 1)
        XCTAssertEqual(restored.tracks[0].name, "雨声")
    }

    func testRestoreUsesFirstAvailableWhenDefaultMissing() {
        let onlyCustom = [
            Preset(
                name: "自定义场景",
                scene: "我的预设",
                group: .mine,
                icon: "💜",
                desc: "desc",
                tracks: [Track(emoji: "🌊", name: "海浪", volume: 0.4)]
            )
        ]

        let restored = AppStateRestorePlanner.restoreScene(
            lastTracksData: "",
            lastPresetName: "",
            availablePresets: onlyCustom,
            defaultPresetName: "雨夜书房",
            fallbackTracks: []
        )

        XCTAssertEqual(restored.selectedPreset, "自定义场景")
        XCTAssertEqual(restored.tracks.first?.name, "海浪")
    }

    func testRestoreFallsBackToPresetTracksWhenDecodedTracksBecomeEmptyAfterSanitize() throws {
        let presets = samplePresets()
        let invalidTracks = [Track(emoji: " ", name: "  ", volume: 0.6)]
        let raw = try encodeTracks(invalidTracks)

        let restored = AppStateRestorePlanner.restoreScene(
            lastTracksData: raw,
            lastPresetName: "森林书桌",
            availablePresets: presets,
            defaultPresetName: "雨夜书房",
            fallbackTracks: []
        )

        XCTAssertEqual(restored.selectedPreset, "森林书桌")
        XCTAssertEqual(restored.tracks.count, 1)
        XCTAssertEqual(restored.tracks.first?.name, "鸟鸣")
    }

    func testRestoreUsesFallbackTracksWhenResolvedPresetHasNoTracks() {
        let presets = [
            Preset(
                name: "空预设",
                scene: "我的预设",
                group: .mine,
                icon: "💜",
                desc: "desc",
                tracks: []
            )
        ]
        let fallback = [Track(emoji: "🔥", name: "篝火", volume: 0.5)]

        let restored = AppStateRestorePlanner.restoreScene(
            lastTracksData: "",
            lastPresetName: "空预设",
            availablePresets: presets,
            defaultPresetName: "不存在默认",
            fallbackTracks: fallback
        )

        XCTAssertEqual(restored.selectedPreset, "空预设")
        XCTAssertEqual(restored.tracks.count, 1)
        XCTAssertEqual(restored.tracks.first?.name, "篝火")
    }

    private func samplePresets() -> [Preset] {
        [
            Preset(
                name: "雨夜书房",
                scene: "助眠",
                group: .officialSleep,
                icon: "🌧️",
                desc: "desc",
                tracks: [Track(emoji: "🌧️", name: "雨声", volume: 0.7)]
            ),
            Preset(
                name: "森林书桌",
                scene: "专注",
                group: .officialFocus,
                icon: "🌲",
                desc: "desc",
                tracks: [Track(emoji: "🐦", name: "鸟鸣", volume: 0.5)]
            )
        ]
    }

    private func encodeTracks(_ tracks: [Track]) throws -> String {
        let data = try JSONEncoder().encode(tracks)
        return String(decoding: data, as: UTF8.self)
    }
}
