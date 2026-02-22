import Foundation

enum PresetTransitionPlanner {

    static func prepareTracks(
        _ tracks: [(name: String, volume: Double)],
        sceneName: String,
        sceneTargetRMS: [String: Double],
        defaultTargetRMS: Double = 0.85,
        maxTracks: Int = TrackPolicy.maxTracks
    ) -> [(name: String, volume: Double)] {
        let sanitized = sanitizeTracks(tracks, maxTracks: maxTracks)
        return SceneAudioTuner.normalizeVolumes(
            sanitized,
            sceneName: sceneName,
            sceneTargetRMS: sceneTargetRMS,
            defaultTargetRMS: defaultTargetRMS
        )
    }

    static func sanitizeTracks(
        _ tracks: [(name: String, volume: Double)],
        maxTracks: Int = TrackPolicy.maxTracks
    ) -> [(name: String, volume: Double)] {
        guard maxTracks > 0 else { return [] }

        var seenNames: Set<String> = []
        var result: [(name: String, volume: Double)] = []
        result.reserveCapacity(min(maxTracks, tracks.count))

        for track in tracks {
            guard result.count < maxTracks else { break }
            let name = track.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seenNames.contains(name) else { continue }

            seenNames.insert(name)
            result.append((name: name, volume: min(1.0, max(0.0, track.volume))))
        }
        return result
    }

    static func hasMeaningfulDifference(
        current: [(name: String, volume: Double)],
        target: [(name: String, volume: Double)],
        volumeTolerance: Double = 0.001
    ) -> Bool {
        let lhs = sanitizeTracks(current)
        let rhs = sanitizeTracks(target)
        guard lhs.count == rhs.count else { return true }

        for idx in lhs.indices {
            if lhs[idx].name != rhs[idx].name { return true }
            if abs(lhs[idx].volume - rhs[idx].volume) > volumeTolerance { return true }
        }
        return false
    }
}
