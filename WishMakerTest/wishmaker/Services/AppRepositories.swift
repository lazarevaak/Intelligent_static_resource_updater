//
//  AppRepositories.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 28.04.2026.

import Foundation

protocol UserRepositoryProtocol {
    func loadUser() -> AppUser?
    func saveUser(_ user: AppUser)
}

protocol ChargingRepositoryProtocol {
    func loadCharging() -> Charging?
    func saveCharging(_ charging: Charging)
}

protocol VehicleRepositoryProtocol {
    var defaultVehicles: [TeslaVehicle] { get }
    var primaryVehicle: TeslaVehicle { get }
    var availableVehicles: [TeslaVehicle] { get }
}

protocol LocationRepositoryProtocol {
    var locations: [AppLocation] { get }
}

protocol AvatarOptionsRepositoryProtocol {
    var options: [String] { get }
}

struct UserDefaultsUserRepository: UserRepositoryProtocol {
    private let defaults: UserDefaults
    private let key = "wishmaker.app.user"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadUser() -> AppUser? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(AppUser.self, from: data)
        } catch {
            AppLogger.persistence.error("Failed to decode user from UserDefaults: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveUser(_ user: AppUser) {
        do {
            let data = try JSONEncoder().encode(user)
            defaults.set(data, forKey: key)
        } catch {
            AppLogger.persistence.error("Failed to encode user for UserDefaults: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct UserDefaultsChargingRepository: ChargingRepositoryProtocol {
    private let defaults: UserDefaults
    private let key = "wishmaker.app.charging"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadCharging() -> Charging? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(Charging.self, from: data)
        } catch {
            AppLogger.persistence.error("Failed to decode charging state from UserDefaults: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func saveCharging(_ charging: Charging) {
        do {
            let data = try JSONEncoder().encode(charging)
            defaults.set(data, forKey: key)
        } catch {
            AppLogger.persistence.error("Failed to encode charging state for UserDefaults: \(error.localizedDescription, privacy: .public)")
        }
    }
}

struct StaticVehicleRepository: VehicleRepositoryProtocol {
    var defaultVehicles: [TeslaVehicle] {
        TeslaVehicleCatalog.defaultVehicles
    }

    var primaryVehicle: TeslaVehicle {
        TeslaVehicleCatalog.primaryVehicle
    }

    var availableVehicles: [TeslaVehicle] {
        TeslaVehicleCatalog.availableVehicles
    }
}

struct StaticLocationRepository: LocationRepositoryProtocol {
    var locations: [AppLocation] {
        LocationsCatalog.locations
    }
}

struct StaticAvatarOptionsRepository: AvatarOptionsRepositoryProtocol {
    var options: [String] {
        AvatarOptionsCatalog.options
    }
}
