//
//  TeslaVehicleCatalog.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation

enum TeslaVehicleCatalog {
    static var defaultVehicles: [TeslaVehicle] {
        loadVehicles()
    }

    static var primaryVehicle: TeslaVehicle {
        defaultVehicles.first ?? fallbackVehicle
    }

    static var availableVehicles: [TeslaVehicle] {
        defaultVehicles
    }

    private static func loadVehicles() -> [TeslaVehicle] {
        AppResourceProvider.shared.decode(
            [TeslaVehicle].self,
            from: AppResourcePath.vehicles
        ) ?? [fallbackVehicle]
    }

    private static let fallbackVehicle = TeslaVehicle(
        id: UUID(uuidString: "1E7FB8D8-1D34-4A53-9A7D-8EACD8B10001") ?? UUID(),
        brandTitle: "Tesla",
        displayName: "Tesla Model 3",
        locationPinTitle: "Your Tesla",
        modelAssetPath: "models/Tesla_2018_Model_3.usdz",
        currentRangeKm: 340,
        batteryLevel: 0.76,
        chargeLimitPercent: 80,
        preferredChargeLimitPercent: 80,
        climateSummary: "Interior 20° C",
        locationSummary: "Berlin Supercharger route",
        dashboardQuickActions: [],
        dashboardRows: [],
        charging: VehicleChargingSnapshot(
            title: "Charging",
            status: "Charging",
            locationName: "Tesla Supercharger Berlin",
            estimatedRangeKm: 340,
            timeUntilFull: "1h 25m",
            chargingSpeedKw: 72,
            addedEnergyKWh: 24,
            addedRangeKm: 150,
            chargingCost: "€12.40",
            recommendedLimitText: "Recommended: 80%",
            controls: []
        ),
        profile: VehicleProfileSnapshot(
            title: "Profile",
            membershipTitle: "Premium driver",
            tripsCount: 148,
            rating: 4.9,
            preferences: [],
            overviewRows: [],
            quickActions: []
        )
    )
}
