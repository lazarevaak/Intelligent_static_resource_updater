//
//  DeviceStorageServiceTests.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
//

import Foundation
import Testing

@testable import ResourceUpdater

struct DeviceStorageServiceTests {
    @Test func freeDiskSpaceIsReportedInMegabytes() throws {
        let service = DeviceStorageService()
        let context = try makeStoreContext()

        let freeDiskSpaceMb = try service.freeDiskSpaceMb(at: context.rootDirectory)

        #expect(freeDiskSpaceMb > 0)
    }
}
