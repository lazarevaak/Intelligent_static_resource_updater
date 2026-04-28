@testable import ResourceUpdateServer
import Crypto
import Foundation
import VaporTesting
import Testing

extension ResourceUpdateServerTests {
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
}
