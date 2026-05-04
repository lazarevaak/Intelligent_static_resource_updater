//
//  ProfileDashboardViewModel.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 28.04.2026.

import Combine
import Foundation

@MainActor
final class ProfileDashboardViewModel: ObservableObject {
    @Published private(set) var user: AppUser
    @Published private(set) var vehicle: TeslaVehicle?
    @Published private(set) var copy: AppCopy
    @Published private(set) var availableVehicles: [TeslaVehicle]

    private let appState: AppState
    private let avatarOptionsRepository: any AvatarOptionsRepositoryProtocol
    private var stateCancellable: AnyCancellable?

    init(
        appState: AppState,
        avatarOptionsRepository: any AvatarOptionsRepositoryProtocol
    ) {
        self.appState = appState
        self.avatarOptionsRepository = avatarOptionsRepository
        user = appState.user
        vehicle = appState.activeVehicle
        copy = appState.copy
        availableVehicles = appState.availableVehicles

        stateCancellable = appState.stateDidChange.sink { [weak self] in
            self?.refresh()
        }
    }

    var avatarOptions: [String] {
        avatarOptionsRepository.options
    }

    func setAvatar(symbolName: String) {
        appState.setAvatar(symbolName: symbolName)
    }

    func selectVehicle(id: UUID) {
        appState.selectVehicle(id: id)
    }

    func bindVehicle(_ vehicle: TeslaVehicle) {
        appState.bindVehicle(vehicle)
    }

    private func refresh() {
        user = appState.user
        vehicle = appState.activeVehicle
        copy = appState.copy
        availableVehicles = appState.availableVehicles
    }
}
