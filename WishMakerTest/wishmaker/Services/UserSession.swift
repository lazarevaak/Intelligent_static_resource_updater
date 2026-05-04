//
//  UserSession.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.

import Combine
import Foundation

@MainActor
final class UserSession {
    @Published private(set) var user: AppUser {
        didSet {
            persist()
        }
    }

    private let userRepository: any UserRepositoryProtocol
    private let vehicleRepository: any VehicleRepositoryProtocol

    init(
        userRepository: any UserRepositoryProtocol,
        vehicleRepository: any VehicleRepositoryProtocol
    ) {
        self.userRepository = userRepository
        self.vehicleRepository = vehicleRepository
        user = userRepository.loadUser() ?? AppUser(vehicles: vehicleRepository.defaultVehicles)
        ensureUserHasVehicleIfNeeded()
        persist()
    }

    var activeVehicle: TeslaVehicle? {
        user.activeVehicle
    }

    var availableVehicles: [TeslaVehicle] {
        let boundIDs = Set(user.vehicles.map(\.id))
        return vehicleRepository.availableVehicles.filter { !boundIDs.contains($0.id) }
    }

    func setLanguage(_ language: AppLanguage) {
        user.languagePreference = language
    }

    func setAvatar(symbolName: String) {
        user.avatarSymbolName = symbolName
    }

    func selectVehicle(id: UUID) {
        user.activeVehicleID = id
    }

    func bindVehicle(_ vehicle: TeslaVehicle) {
        guard !user.vehicles.contains(where: { $0.id == vehicle.id }) else {
            user.activeVehicleID = vehicle.id
            return
        }

        user.vehicles.append(vehicle)
        user.activeVehicleID = vehicle.id
    }

    func ensureUserHasVehicleIfNeeded() {
        guard user.vehicles.isEmpty else {
            if user.activeVehicleID == nil {
                user.activeVehicleID = user.vehicles.first?.id
            }
            return
        }

        user.vehicles = vehicleRepository.defaultVehicles
        user.activeVehicleID = user.vehicles.first?.id
    }

    func refreshVehiclesFromResources() {
        let latestVehicles = vehicleRepository.defaultVehicles
        guard !latestVehicles.isEmpty else { return }

        let latestByID = Dictionary(uniqueKeysWithValues: latestVehicles.map { ($0.id, $0) })
        var updatedUser = user

        if updatedUser.vehicles.isEmpty {
            updatedUser.vehicles = latestVehicles
        } else {
            updatedUser.vehicles = updatedUser.vehicles.map { latestByID[$0.id] ?? $0 }
        }

        if let activeVehicleID = updatedUser.activeVehicleID,
           updatedUser.vehicles.contains(where: { $0.id == activeVehicleID }) {
            if updatedUser != user {
                user = updatedUser
            }
            return
        }

        updatedUser.activeVehicleID = updatedUser.vehicles.first?.id
        if updatedUser != user {
            user = updatedUser
        }
    }

    private func persist() {
        userRepository.saveUser(user)
    }
}
