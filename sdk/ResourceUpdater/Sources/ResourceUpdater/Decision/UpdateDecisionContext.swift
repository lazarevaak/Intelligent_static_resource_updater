//
//  UpdateDecisionContext.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
public struct UpdateDecisionContext: Equatable, Sendable {
    public let updateSizeMb: Double
    public let batteryLevel: Double?
    public let isCharging: Bool
    public let networkType: String
    public let isOnline: Bool
    public let isLowDataMode: Bool
    public let usageCount: Int
    public let usageFrequency: Double
    public let lastUsedHoursAgo: Double?
    public let freeDiskSpaceMb: Double
    public let hourOfDay: Int
    public let isNightTime: Bool

    public init(
        updateSizeMb: Double,
        batteryLevel: Double?,
        isCharging: Bool,
        networkType: String,
        isOnline: Bool,
        isLowDataMode: Bool,
        usageCount: Int,
        usageFrequency: Double,
        lastUsedHoursAgo: Double?,
        freeDiskSpaceMb: Double,
        hourOfDay: Int,
        isNightTime: Bool
    ) {
        self.updateSizeMb = updateSizeMb
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.networkType = networkType
        self.isOnline = isOnline
        self.isLowDataMode = isLowDataMode
        self.usageCount = usageCount
        self.usageFrequency = usageFrequency
        self.lastUsedHoursAgo = lastUsedHoursAgo
        self.freeDiskSpaceMb = freeDiskSpaceMb
        self.hourOfDay = hourOfDay
        self.isNightTime = isNightTime
    }
}
