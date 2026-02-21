import Foundation

struct RestoredSceneState {
    let selectedPreset: String
    let tracks: [Track]
}

enum AppStateRestorePlanner {
    static func restoreScene(
        lastTracksData: String,
        lastPresetName: String,
        availablePresets: [Preset],
        defaultPresetName: String,
        fallbackTracks: [Track]
    ) -> RestoredSceneState {
        let presetByName = Dictionary(uniqueKeysWithValues: availablePresets.map { ($0.name, $0) })
        let defaultPresetTracks = AppBackupCodec.sanitizeTracks(
            presetByName[defaultPresetName]?.tracks ?? fallbackTracks
        )
        let safeFallbackTracks = defaultPresetTracks.isEmpty
            ? AppBackupCodec.sanitizeTracks(fallbackTracks)
            : defaultPresetTracks

        let resolvedPresetName = resolvePresetName(
            rawLastPresetName: lastPresetName,
            availablePresetNames: Set(presetByName.keys),
            defaultPresetName: defaultPresetName
        )

        let decodedTracks = decodeTracks(from: lastTracksData)
        let resolvedTracks: [Track]
        if !decodedTracks.isEmpty {
            resolvedTracks = decodedTracks
        } else if let preset = presetByName[resolvedPresetName] {
            let presetTracks = AppBackupCodec.sanitizeTracks(preset.tracks)
            resolvedTracks = presetTracks.isEmpty ? safeFallbackTracks : presetTracks
        } else {
            resolvedTracks = safeFallbackTracks
        }

        return RestoredSceneState(
            selectedPreset: resolvedPresetName,
            tracks: resolvedTracks
        )
    }

    private static func resolvePresetName(
        rawLastPresetName: String,
        availablePresetNames: Set<String>,
        defaultPresetName: String
    ) -> String {
        let trimmed = rawLastPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, availablePresetNames.contains(trimmed) {
            return trimmed
        }
        if availablePresetNames.contains(defaultPresetName) {
            return defaultPresetName
        }
        return availablePresetNames.sorted().first ?? defaultPresetName
    }

    private static func decodeTracks(from raw: String) -> [Track] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        guard let tracks = try? JSONDecoder().decode([Track].self, from: data) else { return [] }
        return AppBackupCodec.sanitizeTracks(tracks)
    }
}
