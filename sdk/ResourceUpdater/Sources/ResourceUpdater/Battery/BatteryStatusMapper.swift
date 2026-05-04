//
//  BatteryStatusMapper.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

public struct BatteryStatusMapper: Sendable {
    public init() {}

    func map(
        level: Float,
        state: BatteryStatus.ChargingState
    ) -> BatteryStatus {
        let normalizedLevel: Double?
        if level < 0 {
            normalizedLevel = nil
        } else {
            normalizedLevel = min(max(Double(level), 0), 1)
        }

        return BatteryStatus(
            level: normalizedLevel,
            chargingState: state
        )
    }
}
