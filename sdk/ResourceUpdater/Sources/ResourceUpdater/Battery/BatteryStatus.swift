//
//  BatteryStatus.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

public struct BatteryStatus: Sendable {
    public enum ChargingState: Sendable {
        case charging
        case full
        case unplugged
        case unknown
    }

    public let level: Double?
    public let chargingState: ChargingState

    public var isCharging: Bool {
        chargingState == .charging || chargingState == .full
    }

    public init(
        level: Double?,
        chargingState: ChargingState
    ) {
        self.level = level
        self.chargingState = chargingState
    }
}
