//
//  UpdateSizeServiceTests.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
//

import Testing

@testable import ResourceUpdater

struct UpdateSizeServiceTests {
    let service = UpdateSizeService()

    @Test func patchSizeIsUsedWhenPatchExists() {
        let response = makeUpdatesResponse(manifestSize: 10_000_000, patchSize: 1_000_000)

        #expect(service.updateSizeBytes(from: response) == 1_000_000)
    }

    @Test func manifestSizeIsUsedWhenPatchIsMissing() {
        let response = makeUpdatesResponse(manifestSize: 2_000_000, patchSize: nil)

        #expect(service.updateSizeBytes(from: response) == 2_000_000)
    }

    @Test func updateSizeMegabytesIsCalculatedFromBytes() {
        let response = makeUpdatesResponse(manifestSize: 2_097_152, patchSize: nil)

        #expect(service.updateSizeMb(from: response) == 2)
    }

    @Test func featureContainsUpdateSizeMegabytes() {
        let response = makeUpdatesResponse(manifestSize: 10_000_000, patchSize: 524_288)

        #expect(service.makeFeature(from: response).updateSizeMb == 0.5)
    }
}

private func makeUpdatesResponse(manifestSize: Int, patchSize: Int?) -> UpdatesResponse {
    UpdatesResponse(
        decision: patchSize == nil ? "manifest-only" : "patch",
        appId: TestConstants.appID,
        fromVersion: TestConstants.version100,
        latestVersion: TestConstants.version110,
        sdkVersion: TestConstants.sdkVersion,
        reason: "test",
        manifest: makeDescriptor(size: manifestSize),
        patch: patchSize.map(makeDescriptor(size:))
    )
}

private func makeDescriptor(size: Int) -> SignedObjectDescriptor {
    SignedObjectDescriptor(
        url: "https://example.test/object",
        sha256: "hash",
        signature: "signature",
        signatureAlgorithm: "ed25519",
        signatureKeyId: "main",
        size: size
    )
}
