@testable import ResourceUpdateServer
import CryptoKit
import Foundation
import VaporTesting
import Testing

@Suite("App Tests")
struct ResourceUpdateServerTests {
    private let publishToken = "dev-ci-token"
    private let signingPrimaryPrivateKeyBase64 = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
    private let signingSecondaryPrivateKeyBase64 = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
    private let signingKeyId = "test-key-active"
    private let signingSecondaryKeyId = "test-key-legacy"

    @Test("POST + GET latest manifest returns saved manifest")
    func publishAndReadLatestManifest() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "1.0.0"
            let manifest = makeManifest(version: version)

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(.GET, "v1/manifest/\(appId)/latest", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: "X-Manifest-SHA256") != nil)
                #expect(res.headers.first(name: "X-Signature") != nil)
                #expect(res.headers.first(name: "X-Signature-Alg") == "ed25519")
                #expect(res.headers.first(name: "X-Signature-Key-Id") == signingKeyId)
                let decoded = try? res.content.decode(Manifest.self)
                #expect(decoded != nil)
                #expect(decoded?.version == version)
                #expect(decoded?.schemaVersion == 1)
                #expect(decoded?.minSdkVersion == "1.0")
            })
        }
    }

    @Test("GET signing keys returns active and legacy keys")
    func signingKeysEndpoint() async throws {
        try await withConfiguredApp { app in
            try await app.testing().test(.GET, "v1/keys", afterResponse: { res async in
                #expect(res.status == .ok)
                let decoded = try? res.content.decode([SigningPublicKey].self)
                #expect(decoded != nil)
                #expect(decoded?.count == 2)
                let active = decoded?.first(where: { $0.keyId == signingKeyId })
                let legacy = decoded?.first(where: { $0.keyId == signingSecondaryKeyId })
                #expect(active?.active == true)
                #expect(legacy?.active == false)
                #expect(active?.alg == "ed25519")
                #expect(legacy?.alg == "ed25519")
            })

            try await app.testing().test(.GET, "v1/keys/\(signingSecondaryKeyId)", afterResponse: { res async in
                #expect(res.status == .ok)
                let decoded = try? res.content.decode(SigningPublicKey.self)
                #expect(decoded?.keyId == signingSecondaryKeyId)
                #expect(decoded?.active == false)
            })
        }
    }

    @Test("POST with same request-id returns idempotent OK")
    func postIdempotentReplayReturnsOK() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "2.0.0"
            let manifest = makeManifest(version: version)
            let requestId = UUID().uuidString

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("GET patch returns artifact JSON with checksum header")
    func patchArtifactResponse() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let originalPayload = Data("image-v1-content".utf8)
            let originalHash = sha256(originalPayload)
            let changedPayload = Data("image-v2-content".utf8)
            let changedHash = sha256(changedPayload)
            let addedPayload = Data("new-font-content".utf8)
            let addedHash = sha256(addedPayload)

            let fromManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: fromVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: originalHash, size: originalPayload.count),
                    ResourceEntry(path: "config/main.json", hash: hexHash("b"), size: 200)
                ]
            )

            let toManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: toVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: changedHash, size: changedPayload.count),
                    ResourceEntry(path: "fonts/regular.ttf", hash: addedHash, size: addedPayload.count)
                ]
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(fromVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    try req.content.encode(fromManifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/resource/\(appId)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Resource-Path", value: "images/a.png")
                    req.headers.replaceOrAdd(name: "X-Resource-Hash", value: originalHash)
                    req.headers.replaceOrAdd(name: "X-Resource-Size", value: String(originalPayload.count))
                    req.body = .init(data: originalPayload)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/resource/\(appId)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Resource-Path", value: "images/a.png")
                    req.headers.replaceOrAdd(name: "X-Resource-Hash", value: changedHash)
                    req.headers.replaceOrAdd(name: "X-Resource-Size", value: String(changedPayload.count))
                    req.body = .init(data: changedPayload)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/resource/\(appId)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Resource-Path", value: "fonts/regular.ttf")
                    req.headers.replaceOrAdd(name: "X-Resource-Hash", value: addedHash)
                    req.headers.replaceOrAdd(name: "X-Resource-Size", value: String(addedPayload.count))
                    req.body = .init(data: addedPayload)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(toVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    try req.content.encode(toManifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: "X-Patch-SHA256") != nil)
                    let decoded = try? res.content.decode(PatchArtifact.self)
                    #expect(decoded != nil)
                    #expect(decoded?.operations.map(\.op) == ["remove", "add", "replace"])
                    let add = decoded?.operations.first(where: { $0.op == "add" })
                    let replace = decoded?.operations.first(where: { $0.op == "replace" })
                    #expect(add?.dataBase64 != nil)
                    #expect(replace?.dataBase64 == nil)
                    #expect(replace?.delta != nil)
                    if let addBase64 = add?.dataBase64, let addData = Data(base64Encoded: addBase64) {
                        #expect(addData == addedPayload)
                    } else {
                        #expect(Bool(false))
                    }
                    if let replaceDelta = replace?.delta, let replaceData = applyDelta(replaceDelta, on: originalPayload) {
                        #expect(replaceDelta.algorithm == "splice-v1")
                        #expect(replaceDelta.baseHash == originalHash)
                        #expect(replaceDelta.targetHash == changedHash)
                        #expect(replaceData == changedPayload)
                    } else {
                        #expect(Bool(false))
                    }
                }
            )
        }
    }

    @Test("POST patch upload then GET patch returns uploaded artifact")
    func uploadPatchThenGetPatch() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let fromManifest = makeEmptyManifest(version: fromVersion)
            let toManifest = makeEmptyManifest(version: toVersion)
            let requestId = UUID().uuidString
            let patchData = Data(#"{"schemaVersion":1,"appId":"demo","fromVersion":"1.0.0","toVersion":"1.1.0","generatedAt":"2026-01-01T00:00:00Z","operations":[]}"#.utf8)
            let patchHash = sha256(patchData)

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(fromVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    try req.content.encode(fromManifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(toVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    try req.content.encode(toManifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: patchHash)
                    req.headers.replaceOrAdd(name: "X-Patch-Size", value: String(patchData.count))
                    req.body = .init(data: patchData)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: "X-Patch-SHA256") == patchHash)
                    #expect(res.headers.first(name: "X-Signature") != nil)
                    #expect(res.headers.first(name: "X-Signature-Alg") == "ed25519")
                    #expect(res.headers.first(name: "X-Signature-Key-Id") == signingKeyId)
                    #expect(Data(buffer: res.body) == patchData)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: patchHash)
                    req.body = .init(data: patchData)
                },
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )
        }
    }

    @Test("GET updates returns patch and respects sdkVersion")
    func updatesDecisionFlow() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let fromManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: fromVersion,
                generatedAt: Date(),
                resources: []
            )
            let toManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "2.0",
                version: toVersion,
                generatedAt: Date(),
                resources: []
            )
            let patchData = Data(#"{"schemaVersion":1,"appId":"demo","fromVersion":"1.0.0","toVersion":"1.1.0","generatedAt":"2026-01-01T00:00:00Z","operations":[]}"#.utf8)
            let patchHash = sha256(patchData)

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: fromManifest)
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: toManifest)

            try await app.testing().test(
                .POST,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: patchHash)
                    req.body = .init(data: patchData)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=\(fromVersion)&sdkVersion=2.1",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: "X-Updates-SHA256") != nil)
                    #expect(res.headers.first(name: "X-Updates-Signature") != nil)
                    #expect(res.headers.first(name: "X-Updates-Signature-Alg") == "ed25519")
                    #expect(res.headers.first(name: "X-Updates-Signature-Key-Id") == signingKeyId)
                    let decoded = try? res.content.decode(UpdatesResponse.self)
                    #expect(decoded?.decision == "patch")
                    #expect(decoded?.patch != nil)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=\(fromVersion)&sdkVersion=1.5",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: "X-Updates-SHA256") != nil)
                    #expect(res.headers.first(name: "X-Updates-Signature") != nil)
                    let decoded = try? res.content.decode(UpdatesResponse.self)
                    #expect(decoded?.decision == "manifest-only")
                    #expect(decoded?.reason == "sdk-too-old")
                    #expect(decoded?.patch == nil)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=\(toVersion)&sdkVersion=2.1",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: "X-Updates-SHA256") != nil)
                    #expect(res.headers.first(name: "X-Updates-Signature") != nil)
                    let decoded = try? res.content.decode(UpdatesResponse.self)
                    #expect(decoded?.decision == "no-update")
                }
            )
        }
    }

    @Test("POST patch upload with same request-id and different payload returns 409")
    func patchUploadIdempotencyConflict() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let fromManifest = makeEmptyManifest(version: fromVersion)
            let toManifest = makeEmptyManifest(version: toVersion)
            let requestId = UUID().uuidString
            let firstData = Data("first-patch".utf8)
            let secondData = Data("second-patch".utf8)

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: fromManifest)
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: toManifest)

            try await app.testing().test(
                .POST,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: sha256(firstData))
                    req.body = .init(data: firstData)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: sha256(secondData))
                    req.body = .init(data: secondData)
                },
                afterResponse: { res async in
                    #expect(res.status == .conflict)
                }
            )
        }
    }

    @Test("POST patch upload hash mismatch returns 400")
    func patchUploadHashMismatch() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let patchData = Data("patch-content".utf8)

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: makeEmptyManifest(version: fromVersion))
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: makeEmptyManifest(version: toVersion))

            try await app.testing().test(
                .POST,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: hexHash("a"))
                    req.body = .init(data: patchData)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("POST patch upload with missing versions returns 404")
    func patchUploadMissingVersionReturns404() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let patchData = Data("patch-content".utf8)

            try await app.testing().test(
                .POST,
                "v1/patch/\(appId)/from/1.0.0/to/1.1.0/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: sha256(patchData))
                    req.body = .init(data: patchData)
                },
                afterResponse: { res async in
                    #expect(res.status == .notFound)
                }
            )
        }
    }

    @Test("POST with invalid schemaVersion returns 400")
    func invalidSchemaVersionValidation() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "3.0.0"
            let invalid = Manifest(
                schemaVersion: 0,
                minSdkVersion: "1.0",
                version: version,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: hexHash("a"), size: 10)
                ]
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    try req.content.encode(invalid)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("POST without request-id returns 400")
    func postWithoutRequestIdReturnsBadRequest() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "4.0.0"
            let manifest = makeManifest(version: version)

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("POST manifest without token returns 401")
    func postWithoutTokenUnauthorized() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "5.0.0"
            let manifest = makeManifest(version: version)

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                }
            )
        }
    }

    @Test("POST resource upload + GET resource by hash")
    func uploadAndDownloadResource() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let payload = Data("hello-resource".utf8)
            let hash = sha256(payload)

            try await app.testing().test(
                .POST,
                "v1/resource/\(appId)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Resource-Path", value: "assets/hello.txt")
                    req.headers.replaceOrAdd(name: "X-Resource-Hash", value: hash)
                    req.headers.replaceOrAdd(name: "X-Resource-Size", value: String(payload.count))
                    req.body = .init(data: payload)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/resource/\(appId)/hash/\(hash)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(res.headers.first(name: "X-Resource-Hash") == hash)
                    #expect(res.headers.first(name: "X-Resource-Size") == String(payload.count))
                    #expect(Data(buffer: res.body) == payload)
                }
            )
        }
    }

    @Test("POST resource with hash mismatch returns 400")
    func uploadResourceHashMismatch() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let payload = Data("hello-resource".utf8)

            try await app.testing().test(
                .POST,
                "v1/resource/\(appId)/upload",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Resource-Path", value: "assets/hello.txt")
                    req.headers.replaceOrAdd(name: "X-Resource-Hash", value: hexHash("a"))
                    req.headers.replaceOrAdd(name: "X-Resource-Size", value: String(payload.count))
                    req.body = .init(data: payload)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("POST with same request-id and different payload returns 409")
    func postIdempotencyConflictReturnsConflict() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "6.0.0"
            let requestId = UUID().uuidString
            let first = makeManifest(version: version)
            let second = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: version,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: hexHash("e"), size: 111)
                ]
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    try req.content.encode(first)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    try req.content.encode(second)
                },
                afterResponse: { res async in
                    #expect(res.status == .conflict)
                    let envelope = try? res.content.decode(ErrorEnvelope.self)
                    #expect(envelope?.error.code == "conflict")
                }
            )
        }
    }

    @Test("Error response has unified envelope and request-id")
    func errorResponseContainsEnvelopeAndRequestId() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "7.0.0"
            let requestId = "req-\(UUID().uuidString)"

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: requestId)
                    try req.content.encode(makeManifest(version: version))
                },
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                    #expect(res.headers.first(name: "X-Request-Id") == requestId)
                    let envelope = try? res.content.decode(ErrorEnvelope.self)
                    #expect(envelope?.error.code == "unauthorized")
                    #expect(envelope?.error.requestId == requestId)
                }
            )
        }
    }

    @Test("Manifest publish is rollback-safe when artifact upload fails")
    func manifestPublishRollsBackOnArtifactPutFailure() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let storageBackend = MockArtifactStorage()
            let storage = ManifestStorage(publicDirectory: publicDirectory, artifactStorage: storageBackend)
            let appId = "app-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let failedRequestId = UUID().uuidString

            let fromManifest = makeManifest(version: fromVersion)
            let changedPayload = Data("new-image-content".utf8)
            let toManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: toVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: sha256(changedPayload), size: changedPayload.count)
                ]
            )

            _ = try await storage.uploadResource(
                appId: appId,
                path: "images/a.png",
                expectedHash: sha256(changedPayload),
                expectedSize: changedPayload.count,
                data: changedPayload
            )

            let created = try await storage.save(
                fromManifest,
                appId: appId,
                version: fromVersion,
                overwrite: false,
                requestId: UUID().uuidString,
                payloadHash: try payloadHash(fromManifest)
            )
            switch created {
            case .created:
                break
            case .replayed:
                #expect(Bool(false))
            }

            await storageBackend.setFailPut(true)
            do {
                _ = try await storage.save(
                    toManifest,
                    appId: appId,
                    version: toVersion,
                    overwrite: false,
                    requestId: failedRequestId,
                    payloadHash: try payloadHash(toManifest)
                )
                #expect(Bool(false))
            } catch {
                // expected
            }

            do {
                _ = try await storage.load(appId: appId, version: toVersion)
                #expect(Bool(false))
            } catch {
                // expected: rollback removed partial version
            }

            let latest = try await storage.loadLatest(appId: appId)
            #expect(latest.version == fromVersion)

            await storageBackend.setFailPut(false)
            let retry = try await storage.save(
                toManifest,
                appId: appId,
                version: toVersion,
                overwrite: false,
                requestId: failedRequestId,
                payloadHash: try payloadHash(toManifest)
            )
            switch retry {
            case .created:
                break
            case .replayed:
                #expect(Bool(false))
            }
            let latestAfterRetry = try await storage.loadLatest(appId: appId)
            #expect(latestAfterRetry.version == toVersion)
        }
    }

    @Test("Patch upload is rollback-safe when artifact upload fails")
    func patchUploadRollsBackOnArtifactPutFailure() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let storageBackend = MockArtifactStorage()
            let storage = ManifestStorage(publicDirectory: publicDirectory, artifactStorage: storageBackend)
            let appId = "app-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let requestId = UUID().uuidString
            let patchData = Data("patch-artifact".utf8)
            let patchHash = sha256(patchData)

            _ = try await storage.save(
                makeEmptyManifest(version: fromVersion),
                appId: appId,
                version: fromVersion,
                overwrite: false,
                requestId: UUID().uuidString,
                payloadHash: UUID().uuidString
            )
            _ = try await storage.save(
                makeEmptyManifest(version: toVersion),
                appId: appId,
                version: toVersion,
                overwrite: false,
                requestId: UUID().uuidString,
                payloadHash: UUID().uuidString
            )

            await storageBackend.setFailPut(true)
            do {
                _ = try await storage.uploadPatchArtifact(
                    appId: appId,
                    fromVersion: fromVersion,
                    toVersion: toVersion,
                    requestId: requestId,
                    payloadHash: patchHash,
                    expectedHash: patchHash,
                    expectedSize: patchData.count,
                    data: patchData
                )
                #expect(Bool(false))
            } catch {
                // expected
            }

            await storageBackend.setFailPut(false)
            let retry = try await storage.uploadPatchArtifact(
                appId: appId,
                fromVersion: fromVersion,
                toVersion: toVersion,
                requestId: requestId,
                payloadHash: patchHash,
                expectedHash: patchHash,
                expectedSize: patchData.count,
                data: patchData
            )
            switch retry {
            case .created:
                break
            case .replayed:
                #expect(Bool(false))
            }
        }
    }

    @Test("Cleanup keeps latest N versions and removes old data")
    func cleanupKeepsLatestVersions() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let storageBackend = MockArtifactStorage()
            let storage = ManifestStorage(publicDirectory: publicDirectory, artifactStorage: storageBackend)
            let appId = "app-\(UUID().uuidString)"

            let payloadV1 = Data("v1".utf8)
            let payloadV2 = Data("v2".utf8)
            let payloadV3 = Data("v3".utf8)
            let hashV1 = sha256(payloadV1)
            let hashV2 = sha256(payloadV2)
            let hashV3 = sha256(payloadV3)

            _ = try await storage.uploadResource(appId: appId, path: "assets/file.txt", expectedHash: hashV1, expectedSize: payloadV1.count, data: payloadV1)
            _ = try await storage.save(
                Manifest(schemaVersion: 1, minSdkVersion: "1.0", version: "1.0.0", generatedAt: Date(timeIntervalSince1970: 1), resources: [ResourceEntry(path: "assets/file.txt", hash: hashV1, size: payloadV1.count)]),
                appId: appId,
                version: "1.0.0",
                overwrite: false,
                requestId: UUID().uuidString,
                payloadHash: UUID().uuidString
            )

            _ = try await storage.uploadResource(appId: appId, path: "assets/file.txt", expectedHash: hashV2, expectedSize: payloadV2.count, data: payloadV2)
            _ = try await storage.save(
                Manifest(schemaVersion: 1, minSdkVersion: "1.0", version: "1.1.0", generatedAt: Date(timeIntervalSince1970: 2), resources: [ResourceEntry(path: "assets/file.txt", hash: hashV2, size: payloadV2.count)]),
                appId: appId,
                version: "1.1.0",
                overwrite: false,
                requestId: UUID().uuidString,
                payloadHash: UUID().uuidString
            )

            _ = try await storage.uploadResource(appId: appId, path: "assets/file.txt", expectedHash: hashV3, expectedSize: payloadV3.count, data: payloadV3)
            _ = try await storage.save(
                Manifest(schemaVersion: 1, minSdkVersion: "1.0", version: "1.2.0", generatedAt: Date(timeIntervalSince1970: 3), resources: [ResourceEntry(path: "assets/file.txt", hash: hashV3, size: payloadV3.count)]),
                appId: appId,
                version: "1.2.0",
                overwrite: false,
                requestId: UUID().uuidString,
                payloadHash: UUID().uuidString
            )

            let result = try await storage.cleanup(appId: appId, keepLast: 2)
            #expect(result.removedVersions == ["1.0.0"])
            #expect(result.removedPatchArtifacts >= 1)

            let versionsAfter = try await storage.listVersions(appId: appId)
            #expect(versionsAfter == ["1.1.0", "1.2.0"])

            do {
                _ = try await storage.loadResource(appId: appId, hash: hashV1)
                #expect(Bool(false))
            } catch {
                // expected: removed by cleanup
            }
        }
    }

    @Test("Resource load falls back to artifact backend and caches locally")
    func loadResourceFallsBackToBackendAndCaches() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let storageBackend = MockArtifactStorage()
            let storage = ManifestStorage(publicDirectory: publicDirectory, artifactStorage: storageBackend)
            let appId = "app-\(UUID().uuidString)"
            let data = Data("from-backend".utf8)
            let hash = sha256(data)
            let key = "apps/\(appId)/resources/\(hash).bin"
            await storageBackend.seed(key: key, data: data)

            let first = try await storage.loadResource(appId: appId, hash: hash)
            #expect(first == data)
            #expect(await storageBackend.getCallsCount() == 1)

            try await storageBackend.delete(key: key)
            let second = try await storage.loadResource(appId: appId, hash: hash)
            #expect(second == data)
            #expect(await storageBackend.getCallsCount() == 1)
        }
    }

    private func makeManifest(version: String) -> Manifest {
        Manifest(
            schemaVersion: 1,
            minSdkVersion: "1.0",
            version: version,
            generatedAt: Date(),
            resources: [
                ResourceEntry(path: "images/a.png", hash: hexHash("a"), size: 100),
                ResourceEntry(path: "config/main.json", hash: hexHash("b"), size: 200)
            ]
        )
    }

    private func makeEmptyManifest(version: String) -> Manifest {
        Manifest(
            schemaVersion: 1,
            minSdkVersion: "1.0",
            version: version,
            generatedAt: Date(),
            resources: []
        )
    }

    private func publishManifest(app: Application, appId: String, version: String, manifest: Manifest) async throws {
        try await app.testing().test(
            .POST,
            "v1/manifest/\(appId)/version/\(version)",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                try req.content.encode(manifest)
            },
            afterResponse: { res async in
                #expect(res.status == .created)
            }
        )
    }

    private func withConfiguredApp(_ body: (Application) async throws -> Void) async throws {
        setenv("CI_PUBLISH_TOKEN", publishToken, 1)
        setenv("SIGNING_KEYS_JSON", makeSigningKeysJSON(), 1)
        setenv("SIGNING_ACTIVE_KEY_ID", signingKeyId, 1)
        unsetenv("SIGNING_PRIVATE_KEY_BASE64")
        unsetenv("SIGNING_KEY_ID")
        try await withApp(configure: configure, body)
    }

    private func withTemporaryPublicDirectory(_ body: (String) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("resource-update-tests-\(UUID().uuidString)", isDirectory: true)
        let publicDirectory = base.appendingPathComponent("Public", isDirectory: true)
        try FileManager.default.createDirectory(at: publicDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try await body(publicDirectory.path)
    }

    private func payloadHash(_ manifest: Manifest) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        return sha256(data)
    }

    private func hexHash(_ digit: Character) -> String {
        String(repeating: String(digit), count: 64)
    }

    private func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeSigningKeysJSON() -> String {
        #"""
        [
          { "keyId": "\#(signingKeyId)", "privateKeyBase64": "\#(signingPrimaryPrivateKeyBase64)", "createdAt": "2026-04-25T00:00:00Z" },
          { "keyId": "\#(signingSecondaryKeyId)", "privateKeyBase64": "\#(signingSecondaryPrivateKeyBase64)", "createdAt": "2026-01-01T00:00:00Z" }
        ]
        """#
    }

    private func applyDelta(_ delta: BinaryDeltaPatch, on source: Data) -> Data? {
        var output = source
        for operation in delta.operations.reversed() {
            guard operation.offset >= 0,
                  operation.deleteLength >= 0,
                  operation.offset <= output.count,
                  operation.offset + operation.deleteLength <= output.count,
                  let insertData = Data(base64Encoded: operation.dataBase64) else {
                return nil
            }

            output.replaceSubrange(
                operation.offset..<(operation.offset + operation.deleteLength),
                with: insertData
            )
        }
        return output
    }
}

private actor MockArtifactStorage: ArtifactStorage {
    enum MockError: Error {
        case putFailed
    }

    private var objects: [String: Data] = [:]
    private var failPut = false
    private var getCalls = 0

    func put(_ data: Data, key: String, contentType: String?) async throws {
        if failPut {
            throw MockError.putFailed
        }
        objects[key] = data
    }

    func get(key: String) async throws -> Data? {
        getCalls += 1
        return objects[key]
    }

    func delete(key: String) async throws {
        objects.removeValue(forKey: key)
    }

    func setFailPut(_ value: Bool) {
        failPut = value
    }

    func seed(key: String, data: Data) {
        objects[key] = data
    }

    func getCallsCount() -> Int {
        getCalls
    }
}
