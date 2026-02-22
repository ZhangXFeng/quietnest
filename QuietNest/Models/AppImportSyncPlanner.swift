import Foundation

struct AppImportSyncDecision: Equatable {
    let shouldApplyPreset: Bool
    let shouldSetScene: Bool
}

enum AppImportSyncPlanner {
    static func makeDecision(
        currentScene: String,
        currentTracks: [Track],
        restoredScene: String,
        restoredTracks: [Track],
        forceApply: Bool = false
    ) -> AppImportSyncDecision {
        if forceApply {
            return AppImportSyncDecision(shouldApplyPreset: true, shouldSetScene: true)
        }

        let sceneChanged = currentScene != restoredScene
        let tracksChanged = PresetTransitionPlanner.hasMeaningfulDifference(
            current: currentTracks.map { ($0.name, $0.volume) },
            target: restoredTracks.map { ($0.name, $0.volume) }
        )

        return AppImportSyncDecision(
            shouldApplyPreset: sceneChanged || tracksChanged,
            shouldSetScene: sceneChanged
        )
    }
}
