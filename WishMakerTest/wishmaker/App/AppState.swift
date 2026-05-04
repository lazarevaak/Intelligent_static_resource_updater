//
//  AppState.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.

import Combine
import Foundation

@MainActor
final class AppState {
    private let userSession: UserSession
    private let chargingSession: ChargingSessionService
    private let stateDidChangeSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    var stateDidChange: AnyPublisher<Void, Never> {
        stateDidChangeSubject.eraseToAnyPublisher()
    }

    init(
        userRepository: any UserRepositoryProtocol = UserDefaultsUserRepository(),
        chargingRepository: any ChargingRepositoryProtocol = UserDefaultsChargingRepository(),
        vehicleRepository: any VehicleRepositoryProtocol = StaticVehicleRepository(),
        locationRepository: any LocationRepositoryProtocol = StaticLocationRepository()
    ) {
        userSession = UserSession(
            userRepository: userRepository,
            vehicleRepository: vehicleRepository
        )
        chargingSession = ChargingSessionService(
            chargingRepository: chargingRepository,
            locationRepository: locationRepository,
            activeVehicle: userSession.activeVehicle
        )

        bindSessions()
    }

    var user: AppUser {
        userSession.user
    }

    var charging: Charging {
        chargingSession.charging
    }

    var chargingLimitReachedAlertIsPresented: Bool {
        chargingSession.limitReachedAlertIsPresented
    }

    var activeVehicle: TeslaVehicle? {
        userSession.activeVehicle
    }

    var language: AppLanguage {
        user.languagePreference.resolved
    }

    var copy: AppCopy {
        AppCopy(language: user.languagePreference)
    }

    var availableVehicles: [TeslaVehicle] {
        userSession.availableVehicles
    }

    func setLanguage(_ language: AppLanguage) {
        userSession.setLanguage(language)
    }

    func setAvatar(symbolName: String) {
        userSession.setAvatar(symbolName: symbolName)
    }

    func selectVehicle(id: UUID) {
        userSession.selectVehicle(id: id)
        syncChargingWithActiveVehicle()
    }

    func bindVehicle(_ vehicle: TeslaVehicle) {
        userSession.bindVehicle(vehicle)
        syncChargingWithActiveVehicle()
    }

    func bindFirstAvailableVehicle() {
        let previousVehicleID = activeVehicle?.id
        userSession.ensureUserHasVehicleIfNeeded()
        if activeVehicle?.id != previousVehicleID {
            syncChargingWithActiveVehicle()
        }
    }

    func selectChargingStation(_ station: AppLocation) {
        chargingSession.selectChargingStation(station)
    }

    func setChargeLimitPercent(_ percent: Int) {
        chargingSession.setChargeLimitPercent(percent)
    }

    func startCharging() {
        chargingSession.startCharging()
    }

    func stopCharging() {
        chargingSession.stopCharging()
    }

    func setChargeLimitReachedAlertPresented(_ isPresented: Bool) {
        chargingSession.setLimitReachedAlertPresented(isPresented)
    }

    func refreshAfterForeground() {
        chargingSession.refreshAfterForeground()
    }

    func refreshResources() {
        userSession.refreshVehiclesFromResources()
        chargingSession.refreshResources()
        notifyStateDidChange()
    }

    private func bindSessions() {
        userSession.$user
            .dropFirst()
            .sink { [weak self] _ in
                self?.notifyStateDidChange()
            }
            .store(in: &cancellables)

        chargingSession.$charging
            .dropFirst()
            .sink { [weak self] _ in
                self?.notifyStateDidChange()
            }
            .store(in: &cancellables)

        chargingSession.$limitReachedAlertIsPresented
            .dropFirst()
            .sink { [weak self] _ in
                self?.notifyStateDidChange()
            }
            .store(in: &cancellables)
    }

    private func syncChargingWithActiveVehicle() {
        chargingSession.resetForVehicle(activeVehicle)
    }

    private func notifyStateDidChange() {
        stateDidChangeSubject.send()
    }
}
