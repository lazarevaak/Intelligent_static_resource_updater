@testable import ResourceUpdateServer
import Crypto
import Foundation
import VaporTesting
import Testing

extension ResourceUpdateServerTests {
    @Test("OpenAPI spec and Swagger UI are exposed")
    func documentationRoutes() async throws {
        try await withConfiguredApp { app in
            try await app.testing().test(.GET, "openapi.yaml", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType?.description.contains("application/yaml") == true)
                let body = String(buffer: res.body)
                #expect(body.contains("openapi: 3.0.3"))
                #expect(body.contains("/v1/updates/{appId}:"))
            })

            try await app.testing().test(.GET, "docs", afterResponse: { res async in
                #expect(res.status == .ok)
                #expect(res.headers.contentType?.description.contains("text/html") == true)
                let body = String(buffer: res.body)
                #expect(body.contains("SwaggerUIBundle"))
                #expect(body.contains("/openapi.yaml"))
            })
        }
    }

    @Test("Favicon route does not return 404")
    func faviconRoute() async throws {
        try await withConfiguredApp { app in
            try await app.testing().test(.GET, "favicon.ico", afterResponse: { res async in
                #expect(res.status == .noContent)
            })
        }
    }

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

    @Test("GET unknown signing key returns 404")
    func unknownSigningKeyReturnsNotFound() async throws {
        try await withConfiguredApp { app in
            try await app.testing().test(.GET, "v1/keys/missing-key", afterResponse: { res async in
                #expect(res.status == .notFound)
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

    @Test("POST manifest rejects URL and payload version mismatch")
    func manifestVersionMismatchReturnsBadRequest() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let manifest = makeManifest(version: "1.0.0")

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/1.0.1",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
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

    @Test("GET patch meta returns added changed and removed resources")
    func patchMetaResponse() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let oldPayload = Data("old".utf8)
            let newPayload = Data("new".utf8)
            let addedPayload = Data("added".utf8)

            let fromManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: fromVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "keep.txt", hash: sha256(oldPayload), size: oldPayload.count),
                    ResourceEntry(path: "remove.txt", hash: hexHash("a"), size: 10)
                ]
            )
            let toManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: toVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "keep.txt", hash: sha256(newPayload), size: newPayload.count),
                    ResourceEntry(path: "add.txt", hash: sha256(addedPayload), size: addedPayload.count)
                ]
            )

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: fromManifest)
            try await uploadResource(app: app, appId: appId, path: "keep.txt", payload: newPayload, hash: sha256(newPayload))
            try await uploadResource(app: app, appId: appId, path: "add.txt", payload: addedPayload, hash: sha256(addedPayload))
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: toManifest)

            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/meta",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    let decoded = try? res.content.decode(PatchMeta.self)
                    #expect(decoded?.appId == appId)
                    #expect(decoded?.added.map(\.path) == ["add.txt"])
                    #expect(decoded?.changed.map(\.path) == ["keep.txt"])
                    #expect(decoded?.removed == ["remove.txt"])
                }
            )
        }
    }

    @Test("Segmented splice patch keeps multiple isolated edits as separate operations")
    func segmentedSplicePatchResponse() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"
            let originalPayload = Data("prefix-AAAA-middle-BBBB-suffix".utf8)
            let originalHash = sha256(originalPayload)
            let changedPayload = Data("prefix-ZZZZ-middle-YYYY-suffix".utf8)
            let changedHash = sha256(changedPayload)

            let fromManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: fromVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "texts/sample.txt", hash: originalHash, size: originalPayload.count)
                ]
            )

            let toManifest = Manifest(
                schemaVersion: 1,
                minSdkVersion: "1.0",
                version: toVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "texts/sample.txt", hash: changedHash, size: changedPayload.count)
                ]
            )

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: fromManifest)
            try await uploadResource(app: app, appId: appId, path: "texts/sample.txt", payload: originalPayload, hash: originalHash)
            try await uploadResource(app: app, appId: appId, path: "texts/sample.txt", payload: changedPayload, hash: changedHash)
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: toManifest)

            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    let decoded = try? res.content.decode(PatchArtifact.self)
                    let replace = decoded?.operations.first(where: { $0.op == "replace" })
                    #expect(replace?.delta?.algorithm == "splice-v1")
                    #expect((replace?.delta?.operations.count ?? 0) >= 2)
                    if let delta = replace?.delta {
                        let restored = applyDelta(delta, on: originalPayload)
                        #expect(restored == changedPayload)
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

}
