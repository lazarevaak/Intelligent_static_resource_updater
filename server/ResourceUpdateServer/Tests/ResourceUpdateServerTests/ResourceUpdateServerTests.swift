@testable import ResourceUpdateServer
import Crypto
import Foundation
import VaporTesting
import Testing

@Suite("App Tests", .serialized)
struct ResourceUpdateServerTests {
    let publishToken = "dev-ci-token"
    let metricsToken = "dev-metrics-token"
    let metricsAllowedIP = "203.0.113.10"
    let signingPrimaryPrivateKeyBase64 = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
    let signingSecondaryPrivateKeyBase64 = Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
    let signingKeyId = "test-key-active"
    let signingSecondaryKeyId = "test-key-legacy"

    func makeManifest(version: String) -> Manifest {
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

    func makeEmptyManifest(version: String) -> Manifest {
        Manifest(
            schemaVersion: 1,
            minSdkVersion: "1.0",
            version: version,
            generatedAt: Date(),
            resources: []
        )
    }

    func makeServerConfig(metrics: ServerConfig.MetricsConfig? = nil) -> ServerConfig {
        ServerConfig(
            publishToken: publishToken,
            artifactBackend: .local,
            s3: nil,
            signing: .init(
                activeKeyId: signingKeyId,
                keys: [
                    .init(
                        keyId: signingKeyId,
                        privateKeyBase64: signingPrimaryPrivateKeyBase64,
                        createdAt: Date(timeIntervalSince1970: 0)
                    ),
                    .init(
                        keyId: signingSecondaryKeyId,
                        privateKeyBase64: signingSecondaryPrivateKeyBase64,
                        createdAt: Date(timeIntervalSince1970: 1)
                    )
                ]
            ),
            metrics: metrics ?? .init(token: metricsToken, allowlist: [metricsAllowedIP], listener: nil),
            rateLimit: .init(
                backend: .memory,
                updatesPerMinute: 3,
                patchPerMinute: 2,
                sharedDirectory: nil
            ),
            cleanup: nil
        )
    }

    func publishManifest(app: Application, appId: String, version: String, manifest: Manifest) async throws {
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

    func uploadResource(
        app: Application,
        appId: String,
        path: String,
        payload: Data,
        hash: String
    ) async throws {
        try await app.testing().test(
            .POST,
            "v1/resource/\(appId)/upload",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                req.headers.replaceOrAdd(name: "X-Resource-Path", value: path)
                req.headers.replaceOrAdd(name: "X-Resource-Hash", value: hash)
                req.headers.replaceOrAdd(name: "X-Resource-Size", value: String(payload.count))
                req.body = .init(data: payload)
            },
            afterResponse: { res async in
                #expect(res.status == .created || res.status == .ok)
            }
        )
    }

    func uploadPatch(
        app: Application,
        appId: String,
        fromVersion: String,
        toVersion: String,
        payload: Data,
        hash: String
    ) async throws {
        try await app.testing().test(
            .POST,
            "v1/patch/\(appId)/from/\(fromVersion)/to/\(toVersion)/upload",
            beforeRequest: { req in
                req.headers.replaceOrAdd(name: "X-CI-Token", value: publishToken)
                req.headers.replaceOrAdd(name: "X-Request-Id", value: UUID().uuidString)
                req.headers.replaceOrAdd(name: "X-Patch-SHA256", value: hash)
                req.headers.replaceOrAdd(name: "X-Patch-Size", value: String(payload.count))
                req.body = .init(data: payload)
            },
            afterResponse: { res async in
                #expect(res.status == .created || res.status == .ok)
            }
        )
    }

    func withConfiguredApp(_ body: (Application) async throws -> Void) async throws {
        setenv("CI_PUBLISH_TOKEN", publishToken, 1)
        setenv("METRICS_TOKEN", metricsToken, 1)
        setenv("METRICS_ALLOWLIST", metricsAllowedIP, 1)
        setenv("RATE_LIMIT_UPDATES_PER_MINUTE", "3", 1)
        setenv("RATE_LIMIT_PATCH_PER_MINUTE", "2", 1)
        setenv("SIGNING_KEYS_JSON", makeSigningKeysJSON(), 1)
        setenv("SIGNING_ACTIVE_KEY_ID", signingKeyId, 1)
        unsetenv("SIGNING_PRIVATE_KEY_BASE64")
        unsetenv("SIGNING_KEY_ID")
        try await withApp(configure: configure, body)
    }

    func withServerEnvironment<T>(_ values: [String: String], _ body: () throws -> T) throws -> T {
        let keys = [
            "CI_PUBLISH_TOKEN",
            "ARTIFACT_BACKEND",
            "S3_BUCKET",
            "S3_REGION",
            "S3_ENDPOINT",
            "S3_ACCESS_KEY_ID",
            "S3_SECRET_ACCESS_KEY",
            "S3_PATH_STYLE",
            "SIGNING_KEYS_JSON",
            "SIGNING_ACTIVE_KEY_ID",
            "SIGNING_PRIVATE_KEY_BASE64",
            "SIGNING_KEY_ID",
            "METRICS_TOKEN",
            "METRICS_ALLOWLIST",
            "METRICS_PORT",
            "METRICS_BIND_HOST",
            "RATE_LIMIT_BACKEND",
            "RATE_LIMIT_UPDATES_PER_MINUTE",
            "RATE_LIMIT_PATCH_PER_MINUTE",
            "RATE_LIMIT_SHARED_DIR",
            "CLEANUP_INTERVAL_SECONDS",
            "CLEANUP_KEEP_LAST",
            "CLEANUP_APP_IDS"
        ]
        let previous = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, getenv(key).map { String(cString: $0) })
        })

        for key in keys {
            if let value = values[key] {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }

        defer {
            for (key, value) in previous {
                if let value {
                    setenv(key, value, 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        return try body()
    }

    func withTemporaryPublicDirectory(_ body: (String) async throws -> Void) async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("resource-update-tests-\(UUID().uuidString)", isDirectory: true)
        let publicDirectory = base.appendingPathComponent("Public", isDirectory: true)
        try FileManager.default.createDirectory(at: publicDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try await body(publicDirectory.path)
    }

    func payloadHash(_ manifest: Manifest) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        return sha256(data)
    }

    func hexHash(_ digit: Character) -> String {
        String(repeating: String(digit), count: 64)
    }

    func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func makeSigningKeysJSON() -> String {
        #"""
        [
          { "keyId": "\#(signingKeyId)", "privateKeyBase64": "\#(signingPrimaryPrivateKeyBase64)", "createdAt": "2026-04-25T00:00:00Z" },
          { "keyId": "\#(signingSecondaryKeyId)", "privateKeyBase64": "\#(signingSecondaryPrivateKeyBase64)", "createdAt": "2026-01-01T00:00:00Z" }
        ]
        """#
    }

    func applyDelta(_ delta: BinaryDeltaPatch, on source: Data) -> Data? {
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

actor MockArtifactStorage: ArtifactStorage {
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
