import Foundation

struct CrossfadePlan: Equatable {
    let targetVolume: Float
    let steps: Int
    let stepDurationNs: UInt64
}

enum CrossfadePlanner {
    static func makePlan(
        trackCount: Int,
        targetVolume: Float = 0.85
    ) -> CrossfadePlan {
        // 轨道越多，半程淡入/淡出略延长，减少切换瞬间感知突兀
        let halfMs = max(220, min(520, 220 + trackCount * 35))
        let steps = max(8, min(26, Int(round(Double(halfMs) / 20.0))))
        let stepDurationNs = UInt64((halfMs * 1_000_000) / steps)
        return CrossfadePlan(
            targetVolume: min(max(targetVolume, 0), 1),
            steps: steps,
            stepDurationNs: stepDurationNs
        )
    }
}
