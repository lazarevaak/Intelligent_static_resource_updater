//
//  AppDependencies.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 28.04.2026.

import Foundation

@MainActor
struct AppDependencies {
    let userRepository: any UserRepositoryProtocol
    let chargingRepository: any ChargingRepositoryProtocol
    let vehicleRepository: any VehicleRepositoryProtocol
    let locationRepository: any LocationRepositoryProtocol
    let avatarOptionsRepository: any AvatarOptionsRepositoryProtocol
    let favoriteLocationsStore: any FavoriteLocationsStoreProtocol

    static func live(
        persistenceController: PersistenceController = PersistenceController()
    ) -> AppDependencies {
        AppDependencies(
            userRepository: UserDefaultsUserRepository(),
            chargingRepository: UserDefaultsChargingRepository(),
            vehicleRepository: StaticVehicleRepository(),
            locationRepository: StaticLocationRepository(),
            avatarOptionsRepository: StaticAvatarOptionsRepository(),
            favoriteLocationsStore: FavoriteLocationsStore(
                context: persistenceController.container.viewContext
            )
        )
    }
}
