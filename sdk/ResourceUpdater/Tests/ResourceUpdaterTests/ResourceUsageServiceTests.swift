//
//  ResourceUsageServiceTests.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
//

import Foundation
import Testing

@testable import ResourceUpdater

struct ResourceUsageServiceTests {
    @Test func missingResourceHasEmptyUsageSnapshot() async {
        let service = ResourceUsageService(maxAccessCount: 10)

        let snapshot = await service.snapshot(resourcePath: "images/banner.png", at: Date(timeIntervalSince1970: 0))

        #expect(snapshot.usageCount == 0)
        #expect(snapshot.usageFrequency == 0)
        #expect(snapshot.lastUsedHoursAgo == nil)
    }

    @Test func recordedAccessUpdatesCountFrequencyAndLastUsedTime() async throws {
        let service = ResourceUsageService(maxAccessCount: 10)
        let firstDate = Date(timeIntervalSince1970: 0)
        let secondDate = Date(timeIntervalSince1970: 3600)
        let snapshotDate = Date(timeIntervalSince1970: 7200)

        await service.recordAccess(resourcePath: "images/banner.png", at: firstDate)
        await service.recordAccess(resourcePath: "images/banner.png", at: secondDate)

        let snapshot = await service.snapshot(resourcePath: "images/banner.png", at: snapshotDate)

        #expect(snapshot.usageCount == 2)
        #expect(snapshot.usageFrequency == 0.2)
        #expect(try #require(snapshot.lastUsedHoursAgo) == 1)
    }

    @Test func usageFrequencyIsCappedAtOne() async {
        let service = ResourceUsageService(maxAccessCount: 2)

        await service.recordAccess(resourcePath: "texts/message.txt")
        await service.recordAccess(resourcePath: "texts/message.txt")
        await service.recordAccess(resourcePath: "texts/message.txt")

        let snapshot = await service.snapshot(resourcePath: "texts/message.txt")

        #expect(snapshot.usageCount == 3)
        #expect(snapshot.usageFrequency == 1)
    }
}
