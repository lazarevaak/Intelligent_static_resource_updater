//
//  ChargingDashboardViewModel.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 28.04.2026.

import Combine
import Foundation

@MainActor
final class ChargingDashboardViewModel: ObservableObject {
    @Published private(set) var charging: Charging
    @Published private(set) var vehicle: TeslaVehicle?
    @Published private(set) var copy: AppCopy
    @Published private(set) var limitReachedAlertIsPresented: Bool

    private let appState: AppState
    private let locationRepository: any LocationRepositoryProtocol
    private var stateCancellable: AnyCancellable?

    init(
        appState: AppState,
        locationRepository: any LocationRepositoryProtocol
    ) {
        self.appState = appState
        self.locationRepository = locationRepository
        charging = appState.charging
        vehicle = appState.activeVehicle
        copy = appState.copy
        limitReachedAlertIsPresented = appState.chargingLimitReachedAlertIsPresented

        stateCancellable = appState.stateDidChange.sink { [weak self] in
            self?.refresh()
        }
    }

    var chargingStations: [AppLocation] {
        locationRepository.locations.filter { $0.type == .supercharger }
    }

    var chargingVehicleImagePath: String {
        let configuration = AppResourceProvider.shared.decode(
            AppConfiguration.self,
            from: AppResourcePath.appConfiguration
        )
        return configuration?.chargingVehicleImagePath ?? AppResourcePath.defaultChargingVehicleImage
    }

    var batteryPercentText: String {
        "\(Int((charging.batteryLevel * 100).rounded()))%"
    }

    var estimatedRangeText: String {
        "\(estimatedRangeKm) \(copy.batteryRangeSuffix)"
    }

    var powerText: String {
        "\(Int(charging.powerKw)) kW"
    }

    var addedEnergyText: String {
        "+\(charging.addedEnergyKwh.formatted(.number.precision(.fractionLength(1)))) kWh"
    }

    var addedRangeText: String {
        "+\(addedRangeKm) km"
    }

    var chargeLimitText: String {
        "\(charging.chargeLimitPercent)%"
    }

    var minimumChargeLimitText: String {
        "50%"
    }

    var maximumChargeLimitText: String {
        "100%"
    }

    var costText: String {
        "€" + charging.cost.formatted(.number.precision(.fractionLength(2)))
    }

    var statusText: String {
        switch charging.status {
        case .idle, .stopped:
            return copy.inactive
        case .charging:
            return copy.active
        }
    }

    var timeUntilFullText: String {
        let target = Double(charging.chargeLimitPercent) / 100.0
        let remaining = max(0, target - charging.batteryLevel)
        if remaining <= 0 { return "0m" }

        let capacityKwh = 75.0
        let remainingKwh = remaining * capacityKwh
        let hours = remainingKwh / max(1, charging.powerKw)
        let minutes = Int((hours * 60).rounded())
        let h = minutes / 60
        let m = minutes % 60
        if h <= 0 { return "\(m)m" }
        return "\(h)h \(m)m"
    }

    var batteryLevelState: BatteryLevelState {
        let percent = Int((charging.batteryLevel * 100).rounded())
        if percent < 20 { return .critical }
        if percent < 50 { return .medium }
        return .good
    }

    func selectChargingStation(_ station: AppLocation) {
        appState.selectChargingStation(station)
    }

    func startCharging() {
        appState.startCharging()
    }

    func stopCharging() {
        appState.stopCharging()
    }

    func setChargeLimitPercent(_ percent: Int) {
        appState.setChargeLimitPercent(percent)
    }

    func setLimitReachedAlertPresented(_ isPresented: Bool) {
        appState.setChargeLimitReachedAlertPresented(isPresented)
    }

    private func refresh() {
        charging = appState.charging
        vehicle = appState.activeVehicle
        copy = appState.copy
        limitReachedAlertIsPresented = appState.chargingLimitReachedAlertIsPresented
    }

    private var estimatedRangeKm: Int {
        let baseRange = Double(vehicle?.currentRangeKm ?? 340)
        return Int((baseRange * charging.batteryLevel).rounded())
    }

    private var addedRangeKm: Int {
        Int((charging.addedEnergyKwh * 6.0).rounded())
    }
}

enum BatteryLevelState {
    case critical
    case medium
    case good
}
