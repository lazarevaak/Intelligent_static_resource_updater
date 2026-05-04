//
//  BatteryService.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

public final actor BatteryService: BatteryServiceProtocol {
    private let mapper: BatteryStatusMapper

    public init(mapper: BatteryStatusMapper = BatteryStatusMapper()) {
        self.mapper = mapper
#if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
#endif
    }

    deinit {
#if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = false
#endif
    }

    public var currentStatus: BatteryStatus {
        get async {
#if canImport(UIKit)
            await mapper.map(
                level: UIDevice.current.batteryLevel,
                state: UIDevice.current.batteryState.resourceUpdaterChargingState
            )
#else
            BatteryStatus(level: nil, chargingState: .unknown)
#endif
        }
    }
}

#if canImport(UIKit)
private extension UIDevice.BatteryState {
    var resourceUpdaterChargingState: BatteryStatus.ChargingState {
        switch self {
        case .charging:
            return .charging
        case .full:
            return .full
        case .unplugged:
            return .unplugged
        case .unknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}
#endif
