import Foundation

/// Xoshiro256** — 高性能确定性 PRNG（值类型，实时安全）
/// 相同 seed 产生完全一致的序列，用于粒子合成的可复现随机
struct Xoshiro256 {
    private var s: (UInt64, UInt64, UInt64, UInt64)

    init(seed: UInt64) {
        // SplitMix64 展开 seed 为 4 个状态
        var z = seed
        func next() -> UInt64 {
            z &+= 0x9e3779b97f4a7c15
            var r = z
            r = (r ^ (r >> 30)) &* 0xbf58476d1ce4e5b9
            r = (r ^ (r >> 27)) &* 0x94d049bb133111eb
            return r ^ (r >> 31)
        }
        s = (next(), next(), next(), next())
    }

    /// 生成 [0, UInt64.max] 范围随机整数
    mutating func next() -> UInt64 {
        let result = rotl(s.1 &* 5, 7) &* 9
        let t = s.1 << 17
        s.2 ^= s.0
        s.3 ^= s.1
        s.1 ^= s.2
        s.0 ^= s.3
        s.2 ^= t
        s.3 = rotl(s.3, 45)
        return result
    }

    /// 生成 [0, 1) 范围 Float
    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    /// 生成 [min, max) 范围 Float
    mutating func nextFloat(in range: ClosedRange<Float>) -> Float {
        range.lowerBound + nextFloat() * (range.upperBound - range.lowerBound)
    }

    /// 生成 [min, max] 范围 Int
    mutating func nextInt(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    /// 从 seed 派生子种子（用于按轨道分配独立 PRNG）
    static func derive(seed: UInt64, key: String) -> UInt64 {
        var hash = seed
        for byte in key.utf8 {
            hash = hash &* 6364136223846793005 &+ UInt64(byte)
        }
        return hash
    }

    private func rotl(_ x: UInt64, _ k: Int) -> UInt64 {
        (x << k) | (x >> (64 - k))
    }
}
