import Crypto
import Foundation
import Vapor
import NIOCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct RateLimitDecision: Sendable {
    let allowed: Bool
    let retryAfter: Int
}

protocol RateLimitStore: Sendable {
    func consume(key: String, limit: Int, windowSeconds: Int, now: Date) async throws -> RateLimitDecision
}

actor MemoryRateLimitStore: RateLimitStore {
    private struct CounterWindow {
        let windowStartedAt: Int
        var count: Int
    }

    private var counters: [String: CounterWindow] = [:]

    func consume(key: String, limit: Int, windowSeconds: Int, now: Date) async throws -> RateLimitDecision {
        guard limit > 0 else {
            return RateLimitDecision(allowed: true, retryAfter: 0)
        }

        let nowSeconds = Int(now.timeIntervalSince1970)
        let windowStartedAt = (nowSeconds / windowSeconds) * windowSeconds

        if var current = counters[key], current.windowStartedAt == windowStartedAt {
            if current.count >= limit {
                let retryAfter = max((windowStartedAt + windowSeconds) - nowSeconds, 1)
                return RateLimitDecision(allowed: false, retryAfter: retryAfter)
            }
            current.count += 1
            counters[key] = current
            return RateLimitDecision(allowed: true, retryAfter: 0)
        }

        counters[key] = CounterWindow(windowStartedAt: windowStartedAt, count: 1)
        return RateLimitDecision(allowed: true, retryAfter: 0)
    }
}

struct SharedFileRateLimitStore: RateLimitStore {
    private struct CounterWindow: Codable {
        let windowStartedAt: Int
        let count: Int
    }

    private let directoryURL: URL

    init(directory: String) throws {
        self.directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func consume(key: String, limit: Int, windowSeconds: Int, now: Date) async throws -> RateLimitDecision {
        guard limit > 0 else {
            return RateLimitDecision(allowed: true, retryAfter: 0)
        }

        let nowSeconds = Int(now.timeIntervalSince1970)
        let windowStartedAt = (nowSeconds / windowSeconds) * windowSeconds
        let fileURL = rateLimitFileURL(for: key)
        let lockHandle = try openLockHandle(for: fileURL)
        defer {
            _ = flock(lockHandle.fileDescriptor, LOCK_UN)
            try? lockHandle.close()
        }

        guard flock(lockHandle.fileDescriptor, LOCK_EX) == 0 else {
            throw Abort(.internalServerError, reason: "failed to lock shared rate limit store")
        }

        let current = try loadWindow(from: fileURL)
        let active = current?.windowStartedAt == windowStartedAt ? current : nil

        if let active, active.count >= limit {
            let retryAfter = max((windowStartedAt + windowSeconds) - nowSeconds, 1)
            return RateLimitDecision(allowed: false, retryAfter: retryAfter)
        }

        let next = CounterWindow(
            windowStartedAt: windowStartedAt,
            count: (active?.count ?? 0) + 1
        )
        try saveWindow(next, to: fileURL)
        return RateLimitDecision(allowed: true, retryAfter: 0)
    }

    private func rateLimitFileURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent("\(hex).json")
    }

    private func openLockHandle(for fileURL: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        }
        return try FileHandle(forUpdating: fileURL)
    }

    private func loadWindow(from fileURL: URL) throws -> CounterWindow? {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return nil
        }
        let decoder = JSONDecoder()
        return try decoder.decode(CounterWindow.self, from: data)
    }

    private func saveWindow(_ window: CounterWindow, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(window)
        try data.write(to: fileURL, options: .atomic)
    }
}

func makeRateLimitStore(
    config: ServerConfig.RateLimitConfig,
    publicDirectory: String,
    eventLoop: any EventLoop,
    logger: Logger
) throws -> any RateLimitStore {
    switch config.backend {
    case .memory:
        return MemoryRateLimitStore()
    case .sharedFile:
        let directory = config.sharedDirectory ?? URL(fileURLWithPath: publicDirectory, isDirectory: true)
            .appendingPathComponent("rate-limit-store", isDirectory: true)
            .path
        return try SharedFileRateLimitStore(directory: directory)
    }
}
