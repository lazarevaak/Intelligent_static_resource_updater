//
//  TeslaVehicle.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation

struct TeslaVehicle: Codable, Identifiable, Hashable {
    let id: UUID
    let brandTitle: String
    let displayName: String
    let locationPinTitle: String
    let modelAssetPath: String
    let currentRangeKm: Int
    let batteryLevel: Double
    let chargeLimitPercent: Int
    let preferredChargeLimitPercent: Int
    let climateSummary: String
    let locationSummary: String
    let dashboardQuickActions: [VehicleQuickAction]
    let dashboardRows: [VehicleStatusRow]
    let charging: VehicleChargingSnapshot
    let profile: VehicleProfileSnapshot

    var batteryPercent: Int {
        Int((batteryLevel * 100).rounded())
    }

    enum CodingKeys: String, CodingKey {
        case id
        case brandTitle
        case displayName
        case locationPinTitle
        case modelAssetPath
        case modelAssetName
        case modelAssetExtension
        case currentRangeKm
        case batteryLevel
        case chargeLimitPercent
        case preferredChargeLimitPercent
        case climateSummary
        case locationSummary
        case dashboardQuickActions
        case dashboardRows
        case charging
        case profile
    }

    init(
        id: UUID,
        brandTitle: String,
        displayName: String,
        locationPinTitle: String,
        modelAssetPath: String,
        currentRangeKm: Int,
        batteryLevel: Double,
        chargeLimitPercent: Int,
        preferredChargeLimitPercent: Int,
        climateSummary: String,
        locationSummary: String,
        dashboardQuickActions: [VehicleQuickAction],
        dashboardRows: [VehicleStatusRow],
        charging: VehicleChargingSnapshot,
        profile: VehicleProfileSnapshot
    ) {
        self.id = id
        self.brandTitle = brandTitle
        self.displayName = displayName
        self.locationPinTitle = locationPinTitle
        self.modelAssetPath = modelAssetPath
        self.currentRangeKm = currentRangeKm
        self.batteryLevel = batteryLevel
        self.chargeLimitPercent = chargeLimitPercent
        self.preferredChargeLimitPercent = preferredChargeLimitPercent
        self.climateSummary = climateSummary
        self.locationSummary = locationSummary
        self.dashboardQuickActions = dashboardQuickActions
        self.dashboardRows = dashboardRows
        self.charging = charging
        self.profile = profile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        brandTitle = try container.decode(String.self, forKey: .brandTitle)
        displayName = try container.decode(String.self, forKey: .displayName)
        locationPinTitle = try container.decode(String.self, forKey: .locationPinTitle)

        if let modelAssetPath = try container.decodeIfPresent(String.self, forKey: .modelAssetPath) {
            self.modelAssetPath = modelAssetPath
        } else {
            let oldName = try container.decodeIfPresent(String.self, forKey: .modelAssetName)
            let oldExtension = try container.decodeIfPresent(String.self, forKey: .modelAssetExtension)
            if let oldName, let oldExtension {
                modelAssetPath = "models/\(oldName).\(oldExtension)"
            } else {
                modelAssetPath = "models/Tesla_2018_Model_3.usdz"
            }
        }

        currentRangeKm = try container.decode(Int.self, forKey: .currentRangeKm)
        batteryLevel = try container.decode(Double.self, forKey: .batteryLevel)
        chargeLimitPercent = try container.decode(Int.self, forKey: .chargeLimitPercent)
        preferredChargeLimitPercent = try container.decode(Int.self, forKey: .preferredChargeLimitPercent)
        climateSummary = try container.decode(String.self, forKey: .climateSummary)
        locationSummary = try container.decode(String.self, forKey: .locationSummary)
        dashboardQuickActions = try container.decode([VehicleQuickAction].self, forKey: .dashboardQuickActions)
        dashboardRows = try container.decode([VehicleStatusRow].self, forKey: .dashboardRows)
        charging = try container.decode(VehicleChargingSnapshot.self, forKey: .charging)
        profile = try container.decode(VehicleProfileSnapshot.self, forKey: .profile)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(brandTitle, forKey: .brandTitle)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(locationPinTitle, forKey: .locationPinTitle)
        try container.encode(modelAssetPath, forKey: .modelAssetPath)
        try container.encode(currentRangeKm, forKey: .currentRangeKm)
        try container.encode(batteryLevel, forKey: .batteryLevel)
        try container.encode(chargeLimitPercent, forKey: .chargeLimitPercent)
        try container.encode(preferredChargeLimitPercent, forKey: .preferredChargeLimitPercent)
        try container.encode(climateSummary, forKey: .climateSummary)
        try container.encode(locationSummary, forKey: .locationSummary)
        try container.encode(dashboardQuickActions, forKey: .dashboardQuickActions)
        try container.encode(dashboardRows, forKey: .dashboardRows)
        try container.encode(charging, forKey: .charging)
        try container.encode(profile, forKey: .profile)
    }
}

struct VehicleQuickAction: Identifiable, Codable, Hashable {
    enum TintStyle: String, Codable, Hashable {
        case accent
        case muted
        case neutral
    }

    let id: UUID
    let title: String
    let systemName: String
    var isHighlighted: Bool = false
    var tintStyle: TintStyle = .neutral

    init(
        id: UUID = UUID(),
        title: String,
        systemName: String,
        isHighlighted: Bool = false,
        tintStyle: TintStyle = .neutral
    ) {
        self.id = id
        self.title = title
        self.systemName = systemName
        self.isHighlighted = isHighlighted
        self.tintStyle = tintStyle
    }

    enum CodingKeys: String, CodingKey {
        case title
        case systemName
        case isHighlighted
        case tintStyle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        title = try container.decode(String.self, forKey: .title)
        systemName = try container.decode(String.self, forKey: .systemName)
        isHighlighted = try container.decodeIfPresent(Bool.self, forKey: .isHighlighted) ?? false
        tintStyle = try container.decodeIfPresent(TintStyle.self, forKey: .tintStyle) ?? .neutral
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(systemName, forKey: .systemName)
        try container.encode(isHighlighted, forKey: .isHighlighted)
        try container.encode(tintStyle, forKey: .tintStyle)
    }
}

struct VehicleStatusRow: Codable, Hashable {
    let systemName: String
    let title: String
    var subtitle: String? = nil
}

struct VehicleChargingSnapshot: Codable, Hashable {
    let title: String
    let status: String
    let locationName: String
    let estimatedRangeKm: Int
    let timeUntilFull: String
    let chargingSpeedKw: Int
    let addedEnergyKWh: Int
    let addedRangeKm: Int
    let chargingCost: String
    let recommendedLimitText: String
    let controls: [VehicleQuickAction]
}

struct VehicleProfileSnapshot: Codable, Hashable {
    let title: String
    let membershipTitle: String
    let tripsCount: Int
    let rating: Double
    let preferences: [VehicleQuickAction]
    let overviewRows: [VehicleStatusRow]
    let quickActions: [VehicleQuickAction]
}
