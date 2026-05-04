//
//  UpdateContextBuilderTests.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
//

import Foundation
import Testing

@testable import ResourceUpdater

struct UpdateContextBuilderTests {
    @Test func builderCollectsDecisionContextForModel() async throws {
        let usageService = ResourceUsageService(maxAccessCount: 10)
        await usageService.recordAccess(
            resourcePath: TestConstants.messagePath,
            at: Date(timeIntervalSince1970: 3600)
        )

        let builder = UpdateContextBuilder(
            batteryService: FakeBatteryService(
                status: BatteryStatus(level: 0.42, chargingState: .charging)
            ),
            reachabilityService: FakeReachabilityService(
                status: ReachabilityStatus(
                    status: .online,
                    connectionType: .wifi,
                    restricted: .lowDataMode
                )
            ),
            resourceUsageService: usageService,
            deviceStorageService: FakeDeviceStorageService(freeDiskSpaceMb: 512),
            timeContextService: FakeTimeContextService(
                context: TimeContext(hourOfDay: 23, isNightTime: true)
            )
        )

        let response = makeUpdateContextResponse(manifestSize: 10_000_000, patchSize: 1_048_576)
        let context = try await builder.makeContext(
            from: response,
            resourcePath: TestConstants.messagePath,
            storageDirectory: URL(fileURLWithPath: "/tmp"),
            date: Date(timeIntervalSince1970: 7200)
        )

        #expect(context.updateSizeMb == 1)
        #expect(context.batteryLevel == 0.42)
        #expect(context.isCharging)
        #expect(context.networkType == "wifi")
        #expect(context.isOnline)
        #expect(context.isLowDataMode)
        #expect(context.usageCount == 1)
        #expect(context.usageFrequency == 0.1)
        #expect(context.lastUsedHoursAgo == 1)
        #expect(context.freeDiskSpaceMb == 512)
        #expect(context.hourOfDay == 23)
        #expect(context.isNightTime)
    }
}

private final class FakeBatteryService: BatteryServiceProtocol, @unchecked Sendable {
    let status: BatteryStatus

    init(status: BatteryStatus) {
        self.status = status
    }

    var currentStatus: BatteryStatus {
        get async {
            status
        }
    }
}

private final class FakeReachabilityService: ReachabilityServiceProtocol, @unchecked Sendable {
    let status: ReachabilityStatus

    init(status: ReachabilityStatus) {
        self.status = status
    }

    var currentStatus: ReachabilityStatus {
        get async {
            status
        }
    }

    var statusStream: AsyncStream<ReachabilityStatus> {
        get async {
            AsyncStream { continuation in
                continuation.yield(status)
                continuation.finish()
            }
        }
    }
}

private struct FakeDeviceStorageService: DeviceStorageServiceProtocol {
    let freeDiskSpaceMb: Double

    func freeDiskSpaceMb(at directory: URL) throws -> Double {
        freeDiskSpaceMb
    }
}

private struct FakeTimeContextService: TimeContextServiceProtocol {
    let context: TimeContext

    func currentContext(at date: Date) -> TimeContext {
        context
    }
}

private func makeUpdateContextResponse(manifestSize: Int, patchSize: Int?) -> UpdatesResponse {
    UpdatesResponse(
        decision: patchSize == nil ? "manifest-only" : "patch",
        appId: TestConstants.appID,
        fromVersion: TestConstants.version100,
        latestVersion: TestConstants.version110,
        sdkVersion: TestConstants.sdkVersion,
        reason: "test",
        manifest: makeUpdateContextDescriptor(size: manifestSize),
        patch: patchSize.map(makeUpdateContextDescriptor(size:))
    )
}

private func makeUpdateContextDescriptor(size: Int) -> SignedObjectDescriptor {
    SignedObjectDescriptor(
        url: "https://example.test/object",
        sha256: "hash",
        signature: "signature",
        signatureAlgorithm: "ed25519",
        signatureKeyId: "main",
        size: size
    )
}
