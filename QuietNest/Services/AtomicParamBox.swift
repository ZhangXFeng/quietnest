import Foundation
import os

/// 无锁参数容器 — 用于从主线程向音频线程传递参数快照
/// 使用 os_unfair_lock（不会优先级反转，适合音频线程）
final class AtomicParamBox<T> {
    private let storage: UnsafeMutablePointer<T>
    private let unfairLock: UnsafeMutablePointer<os_unfair_lock>

    init(_ initial: T) {
        storage = .allocate(capacity: 1)
        storage.initialize(to: initial)
        unfairLock = .allocate(capacity: 1)
        unfairLock.initialize(to: os_unfair_lock())
    }

    deinit {
        storage.deinitialize(count: 1)
        storage.deallocate()
        unfairLock.deinitialize(count: 1)
        unfairLock.deallocate()
    }

    /// 主线程写入新参数
    func store(_ value: T) {
        os_unfair_lock_lock(unfairLock)
        storage.pointee = value
        os_unfair_lock_unlock(unfairLock)
    }

    /// 音频线程读取最新参数（无 ARC 开销）
    func load() -> T {
        os_unfair_lock_lock(unfairLock)
        let value = storage.pointee
        os_unfair_lock_unlock(unfairLock)
        return value
    }
}
