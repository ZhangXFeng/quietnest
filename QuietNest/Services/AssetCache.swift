import AVFoundation

/// 音频素材缓存 — 加载、解码、LRU 管理
/// 素材从 bundle 加载后解码为 PCM buffer 常驻内存
final class AssetCache {

    private let maxCount: Int
    private var cache: [String: CacheEntry] = [:]  // soundId -> entry
    private var accessOrder: [String] = []          // LRU 顺序，末尾最近
    /// 串行队列，保护 cache/accessOrder 的并发读写安全
    private let queue = DispatchQueue(label: "com.quietnest.assetcache", qos: .userInitiated)

    init(maxCount: Int = 12) {
        self.maxCount = maxCount
    }

    /// 同步加载素材（在 queue 上调用）
    /// 返回解码后的 PCM buffer，如已缓存则直接返回
    func load(_ soundId: String) -> AVAudioPCMBuffer? {
        queue.sync { _load(soundId) }
    }

    private func _load(_ soundId: String) -> AVAudioPCMBuffer? {
        // 命中缓存
        if let entry = cache[soundId] {
            touchLRU(soundId)
            return entry.buffer
        }

        // 从 bundle 加载（可能耗时，但此时已在 queue 上）
        guard let buffer = loadFromBundle(soundId) else {
            return nil
        }

        // LRU 淘汰
        while cache.count >= maxCount {
            evictLRU()
        }

        cache[soundId] = CacheEntry(buffer: buffer)
        accessOrder.append(soundId)
        return buffer
    }

    /// 异步加载素材
    func loadAsync(_ soundId: String, completion: @escaping (AVAudioPCMBuffer?) -> Void) {
        queue.async { [weak self] in
            let buffer = self?._load(soundId)
            DispatchQueue.main.async {
                completion(buffer)
            }
        }
    }

    /// 预加载多个素材
    func preload(_ soundIds: [String], completion: @escaping () -> Void) {
        queue.async { [weak self] in
            for id in soundIds {
                _ = self?._load(id)
            }
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    /// 清除指定素材缓存
    func evict(_ soundId: String) {
        queue.async { [weak self] in
            self?.cache.removeValue(forKey: soundId)
            self?.accessOrder.removeAll { $0 == soundId }
        }
    }

    /// 清除所有缓存
    func evictAll() {
        queue.async { [weak self] in
            self?.cache.removeAll()
            self?.accessOrder.removeAll()
        }
    }

    var cachedSoundIds: [String] { queue.sync { Array(cache.keys) } }

    // MARK: - 内部

    private func loadFromBundle(_ soundId: String) -> AVAudioPCMBuffer? {
        // 尝试多种后缀
        let extensions = ["caf", "wav", "m4a", "aiff"]
        var fileURL: URL?
        for ext in extensions {
            if let url = Bundle.main.url(forResource: soundId, withExtension: ext, subdirectory: "Assets") {
                fileURL = url
                break
            }
            // 也尝试不带子目录
            if let url = Bundle.main.url(forResource: soundId, withExtension: ext) {
                fileURL = url
                break
            }
        }

        guard let url = fileURL else {
            print("[AssetCache] Asset not found: \(soundId)")
            return nil
        }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            // 转换为 48kHz mono Float32
            let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let frameCount = AVAudioFrameCount(audioFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
                return nil
            }

            // 如果源格式和目标格式匹配，直接读取
            if audioFile.processingFormat.sampleRate == 48_000 &&
               audioFile.processingFormat.channelCount == 1 {
                try audioFile.read(into: buffer)
                return buffer
            }

            // 否则用 converter 转换
            guard let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount
            ) else { return nil }
            try audioFile.read(into: sourceBuffer)

            guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: targetFormat) else {
                return nil
            }

            let outputFrameCount = AVAudioFrameCount(
                Double(frameCount) * 48_000 / audioFile.processingFormat.sampleRate
            )
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCount
            ) else { return nil }

            var isDone = false
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if isDone {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                isDone = true
                outStatus.pointee = .haveData
                return sourceBuffer
            }

            var error: NSError?
            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
            if let error {
                print("[AssetCache] Convert error for \(soundId): \(error)")
                return nil
            }

            return outputBuffer
        } catch {
            print("[AssetCache] Load error for \(soundId): \(error)")
            return nil
        }
    }

    private func touchLRU(_ soundId: String) {
        accessOrder.removeAll { $0 == soundId }
        accessOrder.append(soundId)
    }

    private func evictLRU() {
        guard !accessOrder.isEmpty else { return }
        let oldest = accessOrder.removeFirst()
        cache.removeValue(forKey: oldest)
    }
}

private struct CacheEntry {
    let buffer: AVAudioPCMBuffer
}
