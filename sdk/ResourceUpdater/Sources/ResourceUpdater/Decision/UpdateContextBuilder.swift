//
//  UpdateContextBuilder.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

public final class UpdateContextBuilder: Sendable {
    private let updateSizeService: UpdateSizeService
    private let batteryService: BatteryServiceProtocol
    private let reachabilityService: ReachabilityServiceProtocol
    private let resourceUsageService: ResourceUsageServiceProtocol
    private let deviceStorageService: DeviceStorageServiceProtocol
    private let timeContextService: TimeContextServiceProtocol

    public init(
        updateSizeService: UpdateSizeService = UpdateSizeService(),
        batteryService: BatteryServiceProtocol,
        reachabilityService: ReachabilityServiceProtocol,
        resourceUsageService: ResourceUsageServiceProtocol,
        deviceStorageService: DeviceStorageServiceProtocol = DeviceStorageService(),
        timeContextService: TimeContextServiceProtocol = TimeContextService()
    ) {
        self.updateSizeService = updateSizeService
        self.batteryService = batteryService
        self.reachabilityService = reachabilityService
        self.resourceUsageService = resourceUsageService
        self.deviceStorageService = deviceStorageService
        self.timeContextService = timeContextService
    }

    public func makeContext(
        from response: UpdatesResponse,
        resourcePath: String,
        storageDirectory: URL,
        date: Date = Date()
    ) async throws -> UpdateDecisionContext {
        let battery = await batteryService.currentStatus
        let reachability = await reachabilityService.currentStatus
        let usage = await resourceUsageService.snapshot(resourcePath: resourcePath, at: date)
        let time = timeContextService.currentContext(at: date)

        return UpdateDecisionContext(
            updateSizeMb: updateSizeService.updateSizeMb(from: response),
            batteryLevel: battery.level,
            isCharging: battery.isCharging,
            networkType: networkType(from: reachability),
            isOnline: reachability.status == .online,
            isLowDataMode: reachability.restricted == .lowDataMode,
            usageCount: usage.usageCount,
            usageFrequency: usage.usageFrequency,
            lastUsedHoursAgo: usage.lastUsedHoursAgo,
            freeDiskSpaceMb: try deviceStorageService.freeDiskSpaceMb(at: storageDirectory),
            hourOfDay: time.hourOfDay,
            isNightTime: time.isNightTime
        )
    }

    private func networkType(from status: ReachabilityStatus) -> String {
        switch status.connectionType {
        case .wifi:
            return "wifi"
        case .mobile:
            return "mobile"
        }
    }
}
