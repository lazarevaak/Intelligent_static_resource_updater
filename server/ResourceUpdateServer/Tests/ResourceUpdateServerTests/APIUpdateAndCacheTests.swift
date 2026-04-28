@testable import ResourceUpdateServer
import Crypto
import Foundation
import VaporTesting
import Testing

extension ResourceUpdateServerTests {
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

    @Test("GET updates falls back to manifest when query lacks context")
    func updatesFallbackWhenQueryLacksContext() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: makeEmptyManifest(version: fromVersion))
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: makeEmptyManifest(version: toVersion))

            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?sdkVersion=2.1",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    let decoded = try? res.content.decode(UpdatesResponse.self)
                    #expect(decoded?.decision == "manifest-only")
                    #expect(decoded?.reason == "from-version-missing")
                    #expect(decoded?.patch == nil)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=\(fromVersion)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    let decoded = try? res.content.decode(UpdatesResponse.self)
                    #expect(decoded?.decision == "manifest-only")
                    #expect(decoded?.reason == "sdk-version-missing")
                    #expect(decoded?.patch == nil)
                }
            )
        }
    }

    @Test("Performance smoke: GET updates stays under 300ms locally")
    func updatesPerformanceSmoke() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"

            let fromManifest = makeEmptyManifest(version: fromVersion)
            let toManifest = makeEmptyManifest(version: toVersion)
            let patchData = Data(#"{"schemaVersion":1,"appId":"demo","fromVersion":"1.0.0","toVersion":"1.1.0","generatedAt":"2026-01-01T00:00:00Z","operations":[]}"#.utf8)
            let patchHash = sha256(patchData)

            try await publishManifest(app: app, appId: appId, version: fromVersion, manifest: fromManifest)
            try await publishManifest(app: app, appId: appId, version: toVersion, manifest: toManifest)
            try await uploadPatch(
                app: app,
                appId: appId,
                fromVersion: fromVersion,
                toVersion: toVersion,
                payload: patchData,
                hash: patchHash
            )

            let clock = ContinuousClock()
            let started = clock.now
            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=\(fromVersion)&sdkVersion=2.1",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                }
            )
            let elapsed = started.duration(to: clock.now)
            #expect(elapsed < .milliseconds(300))
        }
    }

    @Test("Performance smoke: 5MB resource transfer stays under 5 seconds locally")
    func resourceTransferPerformanceSmoke() async throws {
        try await withConfiguredApp { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let resourcePath = "payloads/five-meg.bin"
            let payload = Data(repeating: 0x5A, count: 5 * 1024 * 1024)
            let hash = sha256(payload)

            let clock = ContinuousClock()
            let uploadStarted = clock.now
            try await uploadResource(app: app, appId: appId, path: resourcePath, payload: payload, hash: hash)
            let uploadElapsed = uploadStarted.duration(to: clock.now)
            #expect(uploadElapsed < .seconds(5))

            let downloadStarted = clock.now
            try await app.testing().test(
                .GET,
                "v1/resource/\(appId)/hash/\(hash)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    #expect(Data(buffer: res.body) == payload)
                }
            )
            let downloadElapsed = downloadStarted.duration(to: clock.now)
            #expect(downloadElapsed < .seconds(5))
        }
    }

    @Test("ETag and 304 work for updates/latest/version/patch")
    func etagAndNotModifiedFlow() async throws {
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

            var etagVersion: String?
            try await app.testing().test(
                .GET,
                "v1/manifest/\(appId)/version/\(toVersion)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    etagVersion = res.headers.first(name: "ETag")
                    #expect(res.headers.first(name: "Cache-Control")?.contains("immutable") == true)
                }
            )
            try await app.testing().test(
                .GET,
                "v1/manifest/\(appId)/version/\(toVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "If-None-Match", value: etagVersion ?? "")
                },
                afterResponse: { res async in
                    #expect(res.status == .notModified)
                }
            )

            var etagLatest: String?
            try await app.testing().test(
                .GET,
                "v1/manifest/\(appId)/latest",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    etagLatest = res.headers.first(name: "ETag")
                    #expect(res.headers.first(name: "Cache-Control")?.contains("must-revalidate") == true)
                }
            )
            try await app.testing().test(
                .GET,
                "v1/manifest/\(appId)/latest",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "If-None-Match", value: etagLatest ?? "")
                },
                afterResponse: { res async in
                    #expect(res.status == .notModified)
                }
            )

            var etagPatch: String?
            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    etagPatch = res.headers.first(name: "ETag")
                    #expect(res.headers.first(name: "Cache-Control")?.contains("immutable") == true)
                }
            )
            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "If-None-Match", value: etagPatch ?? "")
                },
                afterResponse: { res async in
                    #expect(res.status == .notModified)
                }
            )

            var etagUpdates: String?
            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=\(fromVersion)&sdkVersion=2.1",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    etagUpdates = res.headers.first(name: "ETag")
                    #expect(res.headers.first(name: "Cache-Control")?.contains("must-revalidate") == true)
                }
            )
            try await app.testing().test(
                .GET,
                "v1/updates/\(appId)?fromVersion=\(fromVersion)&sdkVersion=2.1",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "If-None-Match", value: etagUpdates ?? "")
                },
                afterResponse: { res async in
                    #expect(res.status == .notModified)
                }
            )
        }
    }

}
