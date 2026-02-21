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

    /// 快速获取已缓存 buffer（同步，供主线程调用）
    /// 队列空闲时几乎立即返回；如无缓存返回 nil，调用方应退回异步路径
    func cachedBuffer(for soundId: String) -> AVAudioPCMBuffer? {
        queue.sync { cache[soundId]?.buffer }
    }

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
            print("[AssetCache] ❌ Asset not found: \(soundId) (tried subdirectory:Assets and root)")
            return nil
        }
        print("[AssetCache] Found: \(url.lastPathComponent)")

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let targetFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let frameCount = AVAudioFrameCount(audioFile.length)
            print("[AssetCache] \(soundId): fileFormat=\(audioFile.fileFormat) processingFormat=\(audioFile.processingFormat) frames=\(frameCount)")

            guard let srcBuf = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat,
                                                frameCapacity: frameCount) else {
                print("[AssetCache] ❌ srcBuf alloc failed for \(soundId)")
                return nil
            }
            try audioFile.read(into: srcBuf)
            print("[AssetCache] Read \(srcBuf.frameLength) frames for \(soundId)")

            guard srcBuf.frameLength > 0 else {
                print("[AssetCache] ❌ Empty audio for \(soundId)")
                return nil
            }

            if audioFile.processingFormat == targetFormat {
                print("[AssetCache] ✓ Direct return (format matches) for \(soundId)")
                return srcBuf
            }

            print("[AssetCache] Converting format for \(soundId): \(audioFile.processingFormat) -> \(targetFormat)")
            guard let converter = AVAudioConverter(from: audioFile.processingFormat, to: targetFormat) else {
                print("[AssetCache] ❌ No converter for \(soundId)")
                return nil
            }
            let outputFrameCount = AVAudioFrameCount(
                Double(srcBuf.frameLength) * 48_000 / audioFile.processingFormat.sampleRate
            )
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                frameCapacity: max(outputFrameCount, 1)) else {
                print("[AssetCache] ❌ outBuf alloc failed for \(soundId)")
                return nil
            }
            var isDone = false
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if isDone { outStatus.pointee = .noDataNow; return nil }
                isDone = true
                outStatus.pointee = .haveData
                return srcBuf
            }
            var error: NSError?
            converter.convert(to: outBuf, error: &error, withInputFrom: inputBlock)
            if let error {
                print("[AssetCache] ❌ Convert error for \(soundId): \(error)")
                return nil
            }
            guard outBuf.frameLength > 0 else {
                print("[AssetCache] ❌ Converter produced 0 frames for \(soundId)")
                return nil
            }
            print("[AssetCache] ✓ Converted \(outBuf.frameLength) frames for \(soundId)")
            return outBuf
        } catch {
            print("[AssetCache] ❌ Load error for \(soundId): \(error)")
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
