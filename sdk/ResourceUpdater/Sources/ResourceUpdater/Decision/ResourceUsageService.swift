//
//  ResourceUsageService.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

public struct ResourceUsageSnapshot: Equatable, Sendable {
    public let usageCount: Int
    public let usageFrequency: Double
    public let lastUsedHoursAgo: Double?

    public init(
        usageCount: Int,
        usageFrequency: Double,
        lastUsedHoursAgo: Double?
    ) {
        self.usageCount = usageCount
        self.usageFrequency = usageFrequency
        self.lastUsedHoursAgo = lastUsedHoursAgo
    }
}

public protocol ResourceUsageServiceProtocol: Sendable {
    func recordAccess(resourcePath: String, at date: Date) async
    func snapshot(resourcePath: String, at date: Date) async -> ResourceUsageSnapshot
}

public actor ResourceUsageService: ResourceUsageServiceProtocol {
    private struct UsageState {
        var accessCount: Int
        var lastUsedAt: Date?
    }

    private let maxAccessCount: Int
    private var states: [String: UsageState]

    public init(maxAccessCount: Int = 100) {
        self.maxAccessCount = max(maxAccessCount, 1)
        self.states = [:]
    }

    public func recordAccess(resourcePath: String, at date: Date = Date()) {
        var state = states[resourcePath] ?? UsageState(accessCount: 0, lastUsedAt: nil)
        state.accessCount += 1
        state.lastUsedAt = date
        states[resourcePath] = state
    }

    public func snapshot(resourcePath: String, at date: Date = Date()) -> ResourceUsageSnapshot {
        guard let state = states[resourcePath] else {
            return ResourceUsageSnapshot(usageCount: 0, usageFrequency: 0, lastUsedHoursAgo: nil)
        }

        let frequency = min(Double(state.accessCount) / Double(maxAccessCount), 1)
        let lastUsedHoursAgo = state.lastUsedAt.map { date.timeIntervalSince($0) / 3600 }

        return ResourceUsageSnapshot(
            usageCount: state.accessCount,
            usageFrequency: frequency,
            lastUsedHoursAgo: lastUsedHoursAgo
        )
    }
}
