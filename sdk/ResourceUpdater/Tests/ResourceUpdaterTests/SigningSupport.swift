import Foundation
@testable import ResourceUpdater

func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
}

func sign<T: Encodable>(_ value: T, signing: SigningFixture) throws -> (data: Data, hash: String, signature: String) {
    let data = try canonicalJSON(value)
    let signature = try signing.privateKey.signature(for: data).base64EncodedString()
    return (data, sha256(data), signature)
}

func makeManifestOnlyUpdates(signing: SigningFixture, manifest: Manifest) -> (payload: UpdatesResponse, headers: [String: String]) {
    let manifestEnvelope = try! sign(manifest, signing: signing)
    let descriptor = SignedObjectDescriptor(
        url: "/v1/manifest/\(TestConstants.appID)/version/\(manifest.version)",
        sha256: manifestEnvelope.hash,
        signature: manifestEnvelope.signature,
        signatureAlgorithm: "ed25519",
        signatureKeyId: "main",
        size: manifestEnvelope.data.count
    )

    let updates = UpdatesResponse(
        decision: "manifest-only",
        appId: TestConstants.appID,
        fromVersion: TestConstants.version100,
        latestVersion: manifest.version,
        sdkVersion: TestConstants.sdkVersion,
        reason: "patch-unavailable",
        manifest: descriptor,
        patch: nil
    )

    let signedUpdates = try! sign(updates, signing: signing)
    return (
        updates,
        [
            "X-Updates-SHA256": signedUpdates.hash,
            "X-Updates-Signature": signedUpdates.signature,
            "X-Updates-Signature-Alg": "ed25519",
            "X-Updates-Signature-Key-Id": "main"
        ]
    )
}

func makePatchUpdates(
    signing: SigningFixture,
    manifest: Manifest,
    patch: PatchArtifact
) throws -> (payload: UpdatesResponse, payloadData: Data, headers: [String: String]) {
    let manifestEnvelope = try sign(manifest, signing: signing)
    let patchEnvelope = try sign(patch, signing: signing)

    let updates = UpdatesResponse(
        decision: "patch",
        appId: TestConstants.appID,
        fromVersion: patch.fromVersion,
        latestVersion: manifest.version,
        sdkVersion: TestConstants.sdkVersion,
        reason: "patch-available",
        manifest: SignedObjectDescriptor(
            url: "/v1/manifest/\(TestConstants.appID)/version/\(manifest.version)",
            sha256: manifestEnvelope.hash,
            signature: manifestEnvelope.signature,
            signatureAlgorithm: "ed25519",
            signatureKeyId: "main",
            size: manifestEnvelope.data.count
        ),
        patch: SignedObjectDescriptor(
            url: "/v1/patch/\(TestConstants.appID)/from/\(patch.fromVersion)/to/\(patch.toVersion)",
            sha256: patchEnvelope.hash,
            signature: patchEnvelope.signature,
            signatureAlgorithm: "ed25519",
            signatureKeyId: "main",
            size: patchEnvelope.data.count
        )
    )

    let signedUpdates = try sign(updates, signing: signing)
    return (
        payload: updates,
        payloadData: signedUpdates.data,
        headers: [
            "X-Updates-SHA256": signedUpdates.hash,
            "X-Updates-Signature": signedUpdates.signature,
            "X-Updates-Signature-Alg": "ed25519",
            "X-Updates-Signature-Key-Id": "main"
        ]
    )
}

func signedManifestResponse(_ manifest: Manifest, signing: SigningFixture) throws -> [String: String] {
    let signed = try sign(manifest, signing: signing)
    return [
        "X-Manifest-SHA256": signed.hash,
        "X-Signature": signed.signature,
        "X-Signature-Alg": "ed25519",
        "X-Signature-Key-Id": "main"
    ]
}
