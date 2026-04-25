@testable import ResourceUpdateServer
import Foundation
import VaporTesting
import Testing

@Suite("App Tests")
struct ResourceUpdateServerTests {
    private let publishToken = "dev-ci-token"

    @Test("POST + GET latest manifest returns saved manifest")
    func publishAndReadLatestManifest() async throws {
        try await withApp(configure: configure) { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "1.0.0"
            let manifest = makeManifest(version: version)

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(.GET, "v1/manifest/\(appId)/latest", afterResponse: { res async in
                #expect(res.status == .ok)
                let decoded = try? res.content.decode(Manifest.self)
                #expect(decoded != nil)
                #expect(decoded?.version == version)
                #expect(decoded?.resources.count == 2)
            })
        }
    }

    @Test("GET manifest by version returns expected version")
    func getManifestByVersion() async throws {
        try await withApp(configure: configure) { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "2.0.0"
            let manifest = makeManifest(version: version)

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(.GET, "v1/manifest/\(appId)/version/\(version)", afterResponse: { res async in
                #expect(res.status == .ok)
                let decoded = try? res.content.decode(Manifest.self)
                #expect(decoded != nil)
                #expect(decoded?.version == version)
            })
        }
    }

    @Test("POST same manifest version twice returns conflict")
    func postConflictForExistingVersion() async throws {
        try await withApp(configure: configure) { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "3.0.0"
            let manifest = makeManifest(version: version)

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
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
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .conflict)
                }
            )
        }
    }

    @Test("GET patch meta returns added/changed/removed")
    func patchMetaDiff() async throws {
        try await withApp(configure: configure) { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"

            let fromManifest = Manifest(
                version: fromVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: "aaaaaaaa", size: 100),
                    ResourceEntry(path: "config/main.json", hash: "bbbbbbbb", size: 200)
                ]
            )

            let toManifest = Manifest(
                version: toVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: "cccccccc", size: 101),
                    ResourceEntry(path: "fonts/regular.ttf", hash: "dddddddd", size: 300)
                ]
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(fromVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
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
                    try req.content.encode(toManifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .created)
                }
            )

            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/meta",
                afterResponse: { res async in
                    #expect(res.status == .ok)
                    let decoded = try? res.content.decode(PatchMeta.self)
                    #expect(decoded != nil)
                    #expect(decoded?.appId == appId)
                    #expect(decoded?.fromVersion == fromVersion)
                    #expect(decoded?.toVersion == toVersion)
                    #expect(decoded?.added.map(\.path) == ["fonts/regular.ttf"])
                    #expect(decoded?.changed.map(\.path) == ["images/a.png"])
                    #expect(decoded?.removed == ["config/main.json"])
                }
            )
        }
    }

    @Test("GET patch returns operations add/replace/remove")
    func patchDocumentDiff() async throws {
        try await withApp(configure: configure) { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let fromVersion = "1.0.0"
            let toVersion = "1.1.0"

            let fromManifest = Manifest(
                version: fromVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: "aaaaaaaa", size: 100),
                    ResourceEntry(path: "config/main.json", hash: "bbbbbbbb", size: 200)
                ]
            )

            let toManifest = Manifest(
                version: toVersion,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: "cccccccc", size: 101),
                    ResourceEntry(path: "fonts/regular.ttf", hash: "dddddddd", size: 300)
                ]
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(fromVersion)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
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
                    let decoded = try? res.content.decode(PatchDocument.self)
                    #expect(decoded != nil)
                    #expect(decoded?.appId == appId)
                    #expect(decoded?.fromVersion == fromVersion)
                    #expect(decoded?.toVersion == toVersion)

                    let ops = decoded?.operations ?? []
                    #expect(ops.count == 3)
                    #expect(ops.map(\.op) == ["remove", "add", "replace"])
                    #expect(ops.map(\.path) == ["config/main.json", "fonts/regular.ttf", "images/a.png"])
                }
            )
        }
    }

    @Test("GET patch meta for missing version returns 404")
    func patchMetaMissingVersionNotFound() async throws {
        try await withApp(configure: configure) { app in
            let appId = "demoapp-\(UUID().uuidString)"
            try await app.testing().test(
                .GET,
                "v1/patch/\(appId)/from/1.0.0/to/2.0.0/meta",
                afterResponse: { res async in
                    #expect(res.status == .notFound)
                }
            )
        }
    }

    @Test("POST with invalid hash returns 400")
    func invalidHashValidation() async throws {
        try await withApp(configure: configure) { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "4.0.0"
            let invalid = Manifest(
                version: version,
                generatedAt: Date(),
                resources: [
                    ResourceEntry(path: "images/a.png", hash: "bad-hash", size: 10)
                ]
            )

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                    try req.content.encode(invalid)
                },
                afterResponse: { res async in
                    #expect(res.status == .badRequest)
                }
            )
        }
    }

    @Test("POST manifest without token returns 401 and error envelope")
    func postWithoutTokenUnauthorized() async throws {
        try await withApp(configure: configure) { app in
            let appId = "demoapp-\(UUID().uuidString)"
            let version = "5.0.0"
            let manifest = makeManifest(version: version)

            try await app.testing().test(
                .POST,
                "v1/manifest/\(appId)/version/\(version)",
                beforeRequest: { req in
                    try req.content.encode(manifest)
                },
                afterResponse: { res async in
                    #expect(res.status == .unauthorized)
                    let decoded = try? res.content.decode(ErrorEnvelope.self)
                    #expect(decoded != nil)
                    #expect(decoded?.error.code == "unauthorized")
                }
            )
        }
    }

    @Test("S3 artifact storage put/delete integration (optional)")
    func s3ArtifactStorageIntegration() async throws {
        guard (Environment.get("RUN_S3_INTEGRATION") ?? "").lowercased() == "true" else {
            return
        }

        let bucket = Environment.get("S3_BUCKET") ?? ""
        let accessKeyId = Environment.get("S3_ACCESS_KEY_ID") ?? ""
        let secretAccessKey = Environment.get("S3_SECRET_ACCESS_KEY") ?? ""
        #expect(!bucket.isEmpty)
        #expect(!accessKeyId.isEmpty)
        #expect(!secretAccessKey.isEmpty)

        let config = ServerConfig.S3Config(
            bucket: bucket,
            region: Environment.get("S3_REGION") ?? "us-east-1",
            endpoint: Environment.get("S3_ENDPOINT"),
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            usePathStyle: (Environment.get("S3_PATH_STYLE") ?? "true").lowercased() == "true"
        )

        let storage = S3ArtifactStorage(config: config)
        let key = "integration-tests/\(UUID().uuidString).json"
        do {
            try await storage.put(Data("{\"ok\":true}".utf8), key: key, contentType: "application/json")
            try await storage.delete(key: key)
        } catch {
            Issue.record("S3 integration failed: \(error)")
        }
        try await storage.shutdown()
    }

    private func makeManifest(version: String) -> Manifest {
        Manifest(
            version: version,
            generatedAt: Date(),
            resources: [
                ResourceEntry(path: "images/a.png", hash: "aaaaaaaa", size: 100),
                ResourceEntry(path: "config/main.json", hash: "bbbbbbbb", size: 200)
            ]
        )
    }
}
