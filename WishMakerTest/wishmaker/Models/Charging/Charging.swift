//
//  ChargingModel.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation

struct Charging: Codable, Hashable {
    
    enum Status: String, Codable, Hashable {
        
        case idle
        case charging
        case stopped
    }

    var status: Status = .idle
    var selectedStation: AppLocation?

    var batteryLevel: Double = 0.5
    var chargeLimitPercent: Int = 80
    var lastBatteryUpdate: Date = Date()
    var addedEnergyKwh: Double = 0
    var cost: Double = 0

    var powerKw: Double {
        selectedStation?.superchargerDetails?.powerKw ?? 0
    }

    var pricePerKwh: Double {
        selectedStation?.superchargerDetails?.pricePerKwh ?? 0
    }

    mutating func reset(batteryLevel: Double, chargeLimitPercent: Int) {
        status = .idle
        selectedStation = nil
        self.batteryLevel = max(0, min(1, batteryLevel))
        self.chargeLimitPercent = max(50, min(100, chargeLimitPercent))
        lastBatteryUpdate = Date()
        addedEnergyKwh = 0
        cost = 0
    }
}
