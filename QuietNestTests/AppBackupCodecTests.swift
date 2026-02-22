import XCTest
@testable import QuietNest

final class AppBackupCodecTests: XCTestCase {

    func testDecodeRejectsUnsupportedVersion() throws {
        let payload = AppBackupPayload(
            version: 2,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            favoritePresetNames: [],
            customPresets: [],
            lastTracks: [],
            lastPresetName: "",
            mixWithOthersEnabled: true,
            analyticsEnabled: true
        )
        let data = try encoded(payload)

        XCTAssertThrowsError(try AppBackupCodec.decodePayload(from: data)) { error in
            guard case AppBackupCodecError.unsupportedVersion(let version) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(version, 2)
        }
    }

    func testDecodeSanitizesFavoritesTracksAndLastPreset() throws {
        let tracks = [
            Track(emoji: "🌧️", name: " 雨声 ", volume: 1.5),
            Track(emoji: "🔥", name: "雨声", volume: 0.4),
            Track(emoji: "🐦", name: " ", volume: 0.2),
            Track(emoji: "🌀", name: "风扇", volume: -0.4)
        ]
        let preset = Preset(
            name: "  我的预设 ",
            scene: "我的预设",
            group: .mine,
            icon: "💜",
            desc: "desc",
            tracks: tracks
        )
        let payload = AppBackupPayload(
            version: 1,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            favoritePresetNames: [" 雨夜书房 ", "雨夜书房", " "],
            customPresets: [preset],
            lastTracks: tracks,
            lastPresetName: "   ",
            mixWithOthersEnabled: true,
            analyticsEnabled: false
        )
        let data = try encoded(payload)

        let decoded = try AppBackupCodec.decodePayload(from: data)

        XCTAssertEqual(decoded.favoritePresetNames, ["雨夜书房"])
        XCTAssertEqual(decoded.lastPresetName, "雨夜书房")
        XCTAssertEqual(decoded.lastTracks.count, 2)
        XCTAssertEqual(decoded.lastTracks[0].name, "雨声")
        XCTAssertEqual(decoded.lastTracks[0].volume, 1.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.lastTracks[1].name, "风扇")
        XCTAssertEqual(decoded.lastTracks[1].volume, 0.0, accuracy: 0.0001)
        XCTAssertEqual(decoded.customPresets.first?.tracks.count, 2)
    }

    func testSanitizeTracksCapsCountToEight() {
        let tracks = (0..<12).map { idx in
            Track(emoji: "🎵", name: "轨道\(idx)", volume: 0.5)
        }
        let sanitized = AppBackupCodec.sanitizeTracks(tracks)
        XCTAssertEqual(sanitized.count, 8)
    }

    func testEncodeDecodeRoundTrip() throws {
        let payload = AppBackupPayload(
            version: 1,
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            favoritePresetNames: ["雨夜书房", "森林书桌"],
            customPresets: [
                Preset(
                    name: "我的预设",
                    scene: "我的预设",
                    group: .mine,
                    icon: "💜",
                    desc: "desc",
                    tracks: [Track(emoji: "🌊", name: "海浪", volume: 0.5)]
                )
            ],
            lastTracks: [Track(emoji: "🌧️", name: "雨声", volume: 0.7)],
            lastPresetName: "雨夜书房",
            mixWithOthersEnabled: true,
            analyticsEnabled: false
        )

        let encoded = try AppBackupCodec.encodePayload(payload, prettyPrinted: true)
        let decoded = try AppBackupCodec.decodePayload(from: encoded)

        XCTAssertEqual(decoded.version, payload.version)
        XCTAssertEqual(decoded.favoritePresetNames, payload.favoritePresetNames)
        XCTAssertEqual(decoded.customPresets.first?.name, "我的预设")
        XCTAssertEqual(decoded.lastTracks.first?.name, "雨声")
        XCTAssertEqual(decoded.lastPresetName, "雨夜书房")
        XCTAssertEqual(decoded.analyticsEnabled, false)
    }

    func testMakeExportPayloadSanitizesAndUsesSupportedVersion() {
        let payload = AppBackupCodec.makeExportPayload(
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            favoritePresetNames: [" 雨夜书房 ", "雨夜书房", ""],
            customPresets: [
                Preset(
                    name: " 我的预设 ",
                    scene: "我的预设",
                    group: .mine,
                    icon: "💜",
                    desc: "desc",
                    tracks: [
                        Track(emoji: "🌧️", name: " 雨声 ", volume: 1.2),
                        Track(emoji: "🔥", name: "雨声", volume: 0.5),
                        Track(emoji: " ", name: " ", volume: 0.5)
                    ]
                )
            ],
            lastTracks: [
                Track(emoji: "🌊", name: " 海浪 ", volume: -0.2),
                Track(emoji: "💧", name: "海浪", volume: 0.5)
            ],
            lastPresetName: "  ",
            mixWithOthersEnabled: true,
            analyticsEnabled: false
        )

        XCTAssertEqual(payload.version, AppBackupCodec.supportedVersion)
        XCTAssertEqual(payload.favoritePresetNames, ["雨夜书房"])
        XCTAssertEqual(payload.customPresets.first?.name, "我的预设")
        XCTAssertEqual(payload.customPresets.first?.tracks.count, 1)
        XCTAssertEqual(payload.customPresets.first?.tracks.first?.name, "雨声")
        XCTAssertEqual(payload.customPresets.first?.tracks.first?.volume, 1.0, accuracy: 0.0001)
        XCTAssertEqual(payload.lastTracks.count, 1)
        XCTAssertEqual(payload.lastTracks.first?.name, "海浪")
        XCTAssertEqual(payload.lastTracks.first?.volume, 0.0, accuracy: 0.0001)
        XCTAssertEqual(payload.lastPresetName, "雨夜书房")
    }

    private func encoded(_ payload: AppBackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }
}
