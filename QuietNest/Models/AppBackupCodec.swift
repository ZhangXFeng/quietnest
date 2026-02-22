import Foundation

enum AppBackupCodecError: LocalizedError {
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "不支持的备份版本 \(version)"
        }
    }
}

enum AppBackupCodec {
    static let supportedVersion = 1

    static func makeExportPayload(
        exportedAt: Date = Date(),
        favoritePresetNames: [String],
        customPresets: [Preset],
        lastTracks: [Track],
        lastPresetName: String,
        mixWithOthersEnabled: Bool,
        analyticsEnabled: Bool
    ) -> AppBackupPayload {
        let favorites = Array(Set(favoritePresetNames.map(trimmed)))
            .filter { !$0.isEmpty }
            .sorted()
        let presets = sanitizePresets(customPresets)
        let tracks = sanitizeTracks(lastTracks)
        let presetName = trimmed(lastPresetName)

        return AppBackupPayload(
            version: supportedVersion,
            exportedAt: exportedAt,
            favoritePresetNames: favorites,
            customPresets: presets,
            lastTracks: tracks,
            lastPresetName: presetName.isEmpty ? "雨夜书房" : presetName,
            mixWithOthersEnabled: mixWithOthersEnabled,
            analyticsEnabled: analyticsEnabled
        )
    }

    static func encodePayload(
        _ payload: AppBackupPayload,
        prettyPrinted: Bool = false
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if prettyPrinted {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(payload)
    }

    static func decodePayload(from data: Data) throws -> AppBackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(AppBackupPayload.self, from: data)
        return try sanitizeImportedPayload(payload)
    }

    static func sanitizeImportedPayload(_ payload: AppBackupPayload) throws -> AppBackupPayload {
        guard payload.version == supportedVersion else {
            throw AppBackupCodecError.unsupportedVersion(payload.version)
        }

        let favorites = Array(Set(payload.favoritePresetNames.map(trimmed)))
            .filter { !$0.isEmpty }
            .sorted()
        let customPresets = sanitizePresets(payload.customPresets)
        let lastTracks = sanitizeTracks(payload.lastTracks)
        let lastPreset = trimmed(payload.lastPresetName)

        return AppBackupPayload(
            version: payload.version,
            exportedAt: payload.exportedAt,
            favoritePresetNames: favorites,
            customPresets: customPresets,
            lastTracks: lastTracks,
            lastPresetName: lastPreset.isEmpty ? "雨夜书房" : lastPreset,
            mixWithOthersEnabled: payload.mixWithOthersEnabled,
            analyticsEnabled: payload.analyticsEnabled
        )
    }

    static func sanitizePresets(_ presets: [Preset]) -> [Preset] {
        presets.map { preset in
            Preset(
                id: preset.id,
                name: trimmed(preset.name),
                scene: preset.scene,
                group: preset.group,
                icon: preset.icon,
                desc: preset.desc,
                tracks: sanitizeTracks(preset.tracks),
                isFavorite: preset.isFavorite
            )
        }
    }

    static func sanitizeTracks(_ tracks: [Track]) -> [Track] {
        var seenNames: Set<String> = []
        var result: [Track] = []
        result.reserveCapacity(min(TrackPolicy.maxTracks, tracks.count))

        for track in tracks {
            guard result.count < TrackPolicy.maxTracks else { break }
            let name = trimmed(track.name)
            guard !name.isEmpty, !seenNames.contains(name) else { continue }

            seenNames.insert(name)
            result.append(
                Track(
                    id: track.id,
                    emoji: track.emoji,
                    name: name,
                    volume: min(1.0, max(0.0, track.volume))
                )
            )
        }
        return result
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
