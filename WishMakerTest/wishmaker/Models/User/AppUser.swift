//
//  AppUser.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation

struct AppUser: Codable, Identifiable, Hashable {
    let id: UUID
    var avatarSymbolName: String
    var languagePreference: AppLanguage
    var vehicles: [TeslaVehicle]
    var activeVehicleID: UUID?

    init(
        id: UUID = UUID(),
        avatarSymbolName: String = "person.fill",
        languagePreference: AppLanguage = .system,
        vehicles: [TeslaVehicle] = [],
        activeVehicleID: UUID? = nil
    ) {
        self.id = id
        self.avatarSymbolName = avatarSymbolName
        self.languagePreference = languagePreference
        self.vehicles = vehicles
        self.activeVehicleID = activeVehicleID ?? vehicles.first?.id
    }

    var activeVehicle: TeslaVehicle? {
        if let activeVehicleID, let vehicle = vehicles.first(where: { $0.id == activeVehicleID }) {
            return vehicle
        }
        return vehicles.first
    }
}
