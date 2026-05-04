//
//  BatteryStatusMapperTests.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
//

import Testing

@testable import ResourceUpdater

struct BatteryStatusMapperTests {
    let mapper = BatteryStatusMapper()

    @Test func negativeBatteryLevelMapsToUnknownLevel() {
        let result = mapper.map(level: -1, state: .unknown)

        #expect(result.level == nil)
        #expect(result.chargingState == .unknown)
        #expect(!result.isCharging)
    }

    @Test func batteryLevelIsClampedToValidRange() {
        let result = mapper.map(level: 1.5, state: .charging)

        #expect(result.level == 1)
        #expect(result.chargingState == .charging)
        #expect(result.isCharging)
    }

    @Test func unpluggedBatteryIsNotCharging() throws {
        let result = mapper.map(level: 0.42, state: .unplugged)

        #expect(abs(try #require(result.level) - 0.42) < 0.0001)
        #expect(result.chargingState == .unplugged)
        #expect(!result.isCharging)
    }

    @Test func fullBatteryCountsAsCharging() {
        let result = mapper.map(level: 1, state: .full)

        #expect(result.level == 1)
        #expect(result.chargingState == .full)
        #expect(result.isCharging)
    }
}
