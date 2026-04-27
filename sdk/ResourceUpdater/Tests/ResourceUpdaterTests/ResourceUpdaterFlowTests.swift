import Foundation
import XCTest
@testable import ResourceUpdater

final class ResourceUpdaterFlowTests: XCTestCase {
    override class func tearDown() {
        MockURLProtocol.requestHandler = nil
    }

    func testApplyUpdatesEndToEndPatchFlow() async throws {
        let context = try makeStoreContext()
        let store = LocalResourceStore(rootDirectory: context.rootDirectory)
        let session = makeMockedSession()
        let signing = try SigningFixture()
        let updater = ResourceUpdater(
            config: makeConfig(storageDirectory: context.rootDirectory),
            session: session
        )

        let oldData = Data("hello-old".utf8)
        let newData = Data("hello-new".utf8)
        let addedData = Data("new-file".utf8)

        try writeResource(oldData, at: "texts/message.txt", in: context.resourcesDirectory)
        try store.save(manifest: makeManifest(
            version: "1.0.0",
            resources: [makeResourceEntry(path: "texts/message.txt", data: oldData)]
        ))

        let manifest = makeManifest(
            version: "1.1.0",
            resources: [
                makeResourceEntry(path: "texts/message.txt", data: newData),
                makeResourceEntry(path: "texts/new.txt", data: addedData)
            ]
        )
        let patch = PatchArtifact(
            schemaVersion: 1,
            appId: "demoapp",
            fromVersion: "1.0.0",
            toVersion: "1.1.0",
            generatedAt: Date(timeIntervalSince1970: 0),
            operations: [
                PatchOperation(
                    op: "replace",
                    path: "texts/message.txt",
                    hash: sha256(newData),
                    size: newData.count,
                    dataBase64: newData.base64EncodedString(),
                    delta: nil
                ),
                PatchOperation(
                    op: "add",
                    path: "texts/new.txt",
                    hash: sha256(addedData),
                    size: addedData.count,
                    dataBase64: addedData.base64EncodedString(),
                    delta: nil
                )
            ]
        )

        let updates = try makePatchUpdates(signing: signing, manifest: manifest, patch: patch)
        let keyData = try canonicalJSON(signing.publicKey)
        let updatesData = updates.payloadData
        let updatesHeaders = updates.headers
        let manifestData = try canonicalJSON(manifest)
        let manifestHeaders = [
            "X-Manifest-SHA256": updates.payload.manifest.sha256,
            "X-Signature": updates.payload.manifest.signature,
            "X-Signature-Alg": updates.payload.manifest.signatureAlgorithm,
            "X-Signature-Key-Id": updates.payload.manifest.signatureKeyId
        ]
        let patchData = try canonicalJSON(patch)
        let patchDescriptor = try XCTUnwrap(updates.payload.patch)
        let patchHeaders = [
            "X-Patch-SHA256": patchDescriptor.sha256,
            "X-Signature": patchDescriptor.signature,
            "X-Signature-Alg": patchDescriptor.signatureAlgorithm,
            "X-Signature-Key-Id": patchDescriptor.signatureKeyId
        ]

        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/v1/updates/demoapp":
                return makeHTTPResponse(bodyData: updatesData, headers: updatesHeaders)
            case "/v1/manifest/demoapp/version/1.1.0":
                return makeHTTPResponse(bodyData: manifestData, headers: manifestHeaders)
            case "/v1/patch/demoapp/from/1.0.0/to/1.1.0":
                return makeHTTPResponse(bodyData: patchData, headers: patchHeaders)
            case "/v1/keys/main":
                return makeHTTPResponse(bodyData: keyData, headers: [:])
            default:
                throw NSError(domain: "UnexpectedURL", code: 1)
            }
        }

        try await updater.applyUpdates()

        XCTAssertEqual(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent("texts/message.txt")), newData)
        XCTAssertEqual(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent("texts/new.txt")), addedData)
        XCTAssertEqual(store.currentVersion(), "1.1.0")
    }

    func testApplyUpdatesFailsWhenManifestHashIsInvalid() async throws {
        let context = try makeStoreContext()
        let session = makeMockedSession()
        let signing = try SigningFixture()
        let updater = ResourceUpdater(
            config: makeConfig(storageDirectory: context.rootDirectory),
            session: session
        )

        let manifest = makeManifest(
            version: "1.1.0",
            resources: [makeResourceEntry(path: "texts/hello.txt", data: Data("hello".utf8))]
        )
        let updates = makeManifestOnlyUpdates(signing: signing, manifest: manifest)
        let updatesData = try canonicalJSON(updates.payload)
        let updatesHeaders = updates.headers
        let keyData = try canonicalJSON(signing.publicKey)
        let manifestData = try canonicalJSON(manifest)
        let invalidManifestHeaders: [String: String] = {
            var headers = try! signedManifestResponse(manifest, signing: signing)
            headers["X-Manifest-SHA256"] = String(repeating: "0", count: 64)
            return headers
        }()

        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/v1/updates/demoapp":
                return makeHTTPResponse(bodyData: updatesData, headers: updatesHeaders)
            case "/v1/manifest/demoapp/version/1.1.0":
                return makeHTTPResponse(bodyData: manifestData, headers: invalidManifestHeaders)
            case "/v1/keys/main":
                return makeHTTPResponse(bodyData: keyData, headers: [:])
            default:
                throw NSError(domain: "UnexpectedURL", code: 1)
            }
        }

        do {
            try await updater.applyUpdates()
            XCTFail("expected hash mismatch")
        } catch let error as ResourceUpdaterError {
            guard case .hashMismatch = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testApplyUpdatesFailsWhenManifestSignatureIsInvalid() async throws {
        let context = try makeStoreContext()
        let session = makeMockedSession()
        let signing = try SigningFixture()
        let updater = ResourceUpdater(
            config: makeConfig(storageDirectory: context.rootDirectory),
            session: session
        )

        let manifest = makeManifest(
            version: "1.1.0",
            resources: [makeResourceEntry(path: "texts/hello.txt", data: Data("hello".utf8))]
        )
        let badSignature = Data("broken-signature".utf8).base64EncodedString()
        let manifestEnvelope = try sign(manifest, signing: signing)
        let manifestDescriptor = SignedObjectDescriptor(
            url: "/v1/manifest/demoapp/version/\(manifest.version)",
            sha256: manifestEnvelope.hash,
            signature: badSignature,
            signatureAlgorithm: "ed25519",
            signatureKeyId: "main",
            size: manifestEnvelope.data.count
        )
        let updatesPayload = UpdatesResponse(
            decision: "manifest-only",
            appId: "demoapp",
            fromVersion: "1.0.0",
            latestVersion: manifest.version,
            sdkVersion: "1.0",
            reason: "patch-unavailable",
            manifest: manifestDescriptor,
            patch: nil
        )
        let updatesEnvelope = try sign(updatesPayload, signing: signing)
        let updatesData = updatesEnvelope.data
        let updatesHeaders = [
            "X-Updates-SHA256": updatesEnvelope.hash,
            "X-Updates-Signature": updatesEnvelope.signature,
            "X-Updates-Signature-Alg": "ed25519",
            "X-Updates-Signature-Key-Id": "main"
        ]
        let keyData = try canonicalJSON(signing.publicKey)
        let manifestData = try canonicalJSON(manifest)
        let invalidManifestHeaders: [String: String] = {
            var headers = try! signedManifestResponse(manifest, signing: signing)
            headers["X-Signature"] = badSignature
            return headers
        }()

        MockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/v1/updates/demoapp":
                return makeHTTPResponse(bodyData: updatesData, headers: updatesHeaders)
            case "/v1/manifest/demoapp/version/1.1.0":
                return makeHTTPResponse(bodyData: manifestData, headers: invalidManifestHeaders)
            case "/v1/keys/main":
                return makeHTTPResponse(bodyData: keyData, headers: [:])
            default:
                throw NSError(domain: "UnexpectedURL", code: 1)
            }
        }

        do {
            try await updater.applyUpdates()
            XCTFail("expected signature verification failure")
        } catch let error as ResourceUpdaterError {
            guard case .signatureVerificationFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
