@testable import ResourceUpdateServer
import Crypto
import Foundation
import VaporTesting
import Testing

extension ResourceUpdateServerTests {
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

    @Test("Background cleanup worker cleans configured apps")
    func backgroundCleanupWorkerRunOnce() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let artifactStorage = MockArtifactStorage()
            let storage = ManifestStorage(publicDirectory: publicDirectory, artifactStorage: artifactStorage)
            let logger = Logger(label: "background-cleanup-test")

            let appA = "app-a-\(UUID().uuidString)"
            let appB = "app-b-\(UUID().uuidString)"

            for (appId, versions) in [(appA, ["1.0.0", "1.1.0", "1.2.0"]), (appB, ["2.0.0", "2.1.0", "2.2.0"])] {
                for version in versions {
                    _ = try await storage.save(
                        makeEmptyManifest(version: version),
                        appId: appId,
                        version: version,
                        overwrite: false,
                        requestId: UUID().uuidString,
                        payloadHash: UUID().uuidString
                    )
                }
            }

            let worker = BackgroundCleanupWorker(
                storage: storage,
                config: .init(intervalSeconds: 60, keepLast: 1, appIds: [appA, appB]),
                logger: logger
            )

            await worker.runOnce()

            let versionsA = try await storage.listVersions(appId: appA)
            let versionsB = try await storage.listVersions(appId: appB)
            #expect(versionsA.count == 1)
            #expect(versionsB.count == 1)
        }
    }

    @Test("Background cleanup worker discovers app ids when none configured")
    func backgroundCleanupWorkerDiscoversAppIds() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let storage = ManifestStorage(publicDirectory: publicDirectory, artifactStorage: LocalArtifactStorage(publicDirectory: publicDirectory))
            let appId = "app-discovered-\(UUID().uuidString)"

            _ = try await storage.save(
                makeEmptyManifest(version: "1.0.0"),
                appId: appId,
                version: "1.0.0",
                overwrite: false,
                requestId: UUID().uuidString,
                payloadHash: UUID().uuidString
            )
            _ = try await storage.save(
                makeEmptyManifest(version: "1.1.0"),
                appId: appId,
                version: "1.1.0",
                overwrite: false,
                requestId: UUID().uuidString,
                payloadHash: UUID().uuidString
            )

            let worker = BackgroundCleanupWorker(
                storage: storage,
                config: .init(intervalSeconds: 1, keepLast: 1, appIds: nil),
                logger: Logger(label: "background-cleanup-discovery-test")
            )

            await worker.runOnce()

            #expect(try await storage.listVersions(appId: appId) == ["1.1.0"])
        }
    }

    @Test("Shared-file rate limit store shares counters across instances")
    func sharedFileRateLimitStoreSharesCounters() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let sharedDirectory = URL(fileURLWithPath: publicDirectory, isDirectory: true)
                .appendingPathComponent("shared-rate-limit", isDirectory: true)
                .path
            let first = try SharedFileRateLimitStore(directory: sharedDirectory)
            let second = try SharedFileRateLimitStore(directory: sharedDirectory)
            let now = Date(timeIntervalSince1970: 1_700_000_000)

            let firstResult = try await first.consume(
                key: "updates:198.51.100.1:demoapp",
                limit: 2,
                windowSeconds: 60,
                now: now
            )
            #expect(firstResult.allowed == true)

            let secondResult = try await second.consume(
                key: "updates:198.51.100.1:demoapp",
                limit: 2,
                windowSeconds: 60,
                now: now
            )
            #expect(secondResult.allowed == true)

            let thirdResult = try await first.consume(
                key: "updates:198.51.100.1:demoapp",
                limit: 2,
                windowSeconds: 60,
                now: now
            )
            #expect(thirdResult.allowed == false)
            #expect(thirdResult.retryAfter > 0)
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

    @Test("Local artifact storage sanitizes traversal segments")
    func localArtifactStorageSanitizesTraversalSegments() async throws {
        try await withTemporaryPublicDirectory { publicDirectory in
            let storage = LocalArtifactStorage(publicDirectory: publicDirectory)
            let payload = Data("safe-local-artifact".utf8)

            try await storage.put(payload, key: "../unsafe/file.bin", contentType: "application/octet-stream")

            let sanitized = try await storage.get(key: "_/unsafe/file.bin")
            let traversal = try await storage.get(key: "../unsafe/file.bin")
            #expect(sanitized == payload)
            #expect(traversal == payload)

            try await storage.delete(key: "../unsafe/file.bin")
            let removed = try await storage.get(key: "_/unsafe/file.bin")
            #expect(removed == nil)

            try await storage.delete(key: "../unsafe/file.bin")
        }
    }

    @Test("S3 artifact storage validates bucket before network calls")
    func s3ArtifactStorageRequiresBucket() async throws {
        let storage = S3ArtifactStorage(
            config: .init(
                bucket: "",
                region: "us-east-1",
                endpoint: nil,
                accessKeyId: "test",
                secretAccessKey: "test",
                usePathStyle: true
            )
        )
        defer {
            Task { try? await storage.shutdown() }
        }

        await #expect(throws: (any Error).self) {
            try await storage.put(Data("payload".utf8), key: "object", contentType: nil)
        }
        await #expect(throws: (any Error).self) {
            _ = try await storage.get(key: "object")
        }
        await #expect(throws: (any Error).self) {
            try await storage.delete(key: "object")
        }
    }

    @Test("Rate limit store allows zero limit and resets by time window")
    func rateLimitStoreAllowsZeroLimitAndResetsByWindow() async throws {
        let memory = MemoryRateLimitStore()
        let now = Date(timeIntervalSince1970: 100)

        let unlimited = try await memory.consume(key: "updates:ip:app", limit: 0, windowSeconds: 60, now: now)
        #expect(unlimited.allowed)

        let first = try await memory.consume(key: "updates:ip:app", limit: 1, windowSeconds: 60, now: now)
        let limited = try await memory.consume(key: "updates:ip:app", limit: 1, windowSeconds: 60, now: now)
        let nextWindow = try await memory.consume(
            key: "updates:ip:app",
            limit: 1,
            windowSeconds: 60,
            now: Date(timeIntervalSince1970: 180)
        )

        #expect(first.allowed)
        #expect(!limited.allowed)
        #expect(limited.retryAfter > 0)
        #expect(nextWindow.allowed)
    }
}
