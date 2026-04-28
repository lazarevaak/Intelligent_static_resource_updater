@testable import ResourceUpdateServer
import Crypto
import Foundation
import VaporTesting
import Testing

extension ResourceUpdateServerTests {
    @Test("Server config reads S3 metrics cleanup and shared rate limit environment")
    func serverConfigReadsExtendedEnvironment() throws {
        try withServerEnvironment(
            [
                "CI_PUBLISH_TOKEN": publishToken,
                "ARTIFACT_BACKEND": "s3",
                "S3_BUCKET": "resource-updates",
                "S3_REGION": "ru-central1",
                "S3_ENDPOINT": "https://storage.yandexcloud.net",
                "S3_ACCESS_KEY_ID": "key",
                "S3_SECRET_ACCESS_KEY": "secret",
                "S3_PATH_STYLE": "false",
                "SIGNING_KEYS_JSON": makeSigningKeysJSON(),
                "SIGNING_ACTIVE_KEY_ID": signingKeyId,
                "METRICS_TOKEN": " metrics-token ",
                "METRICS_ALLOWLIST": "127.0.0.1, 203.0.113.10",
                "METRICS_PORT": "9091",
                "METRICS_BIND_HOST": "",
                "RATE_LIMIT_BACKEND": "shared-file",
                "RATE_LIMIT_UPDATES_PER_MINUTE": "7",
                "RATE_LIMIT_PATCH_PER_MINUTE": "4",
                "RATE_LIMIT_SHARED_DIR": " /tmp/rate-limit ",
                "CLEANUP_INTERVAL_SECONDS": "30",
                "CLEANUP_KEEP_LAST": "2",
                "CLEANUP_APP_IDS": "app-a, app-b"
            ]
        ) {
            let config = try ServerConfig.fromEnvironment()

            #expect(config.publishToken == publishToken)
            #expect(config.artifactBackend == .s3)
            #expect(config.s3?.bucket == "resource-updates")
            #expect(config.s3?.region == "ru-central1")
            #expect(config.s3?.endpoint == "https://storage.yandexcloud.net")
            #expect(config.s3?.usePathStyle == false)
            #expect(config.metrics.token == "metrics-token")
            #expect(config.metrics.allowlist == ["127.0.0.1", "203.0.113.10"])
            #expect(config.metrics.listener?.host == "127.0.0.1")
            #expect(config.metrics.listener?.port == 9091)
            #expect(config.rateLimit.backend == .sharedFile)
            #expect(config.rateLimit.updatesPerMinute == 7)
            #expect(config.rateLimit.patchPerMinute == 4)
            #expect(config.rateLimit.sharedDirectory == "/tmp/rate-limit")
            #expect(config.cleanup?.intervalSeconds == 30)
            #expect(config.cleanup?.keepLast == 2)
            #expect(config.cleanup?.appIds == ["app-a", "app-b"])
        }
    }

    @Test("Server config supports single signing key compatibility mode")
    func serverConfigSupportsSingleSigningKeyCompatibilityMode() throws {
        try withServerEnvironment(
            [
                "CI_PUBLISH_TOKEN": publishToken,
                "SIGNING_PRIVATE_KEY_BASE64": signingPrimaryPrivateKeyBase64,
                "SIGNING_KEY_ID": "single-key",
                "METRICS_TOKEN": " ",
                "METRICS_ALLOWLIST": "",
                "RATE_LIMIT_UPDATES_PER_MINUTE": "-1",
                "RATE_LIMIT_PATCH_PER_MINUTE": "-5"
            ]
        ) {
            let config = try ServerConfig.fromEnvironment()

            #expect(config.artifactBackend == .local)
            #expect(config.s3 == nil)
            #expect(config.signing.activeKeyId == "single-key")
            #expect(config.signing.keys.count == 1)
            #expect(config.metrics.token == nil)
            #expect(!config.metrics.isEnabled)
            #expect(config.rateLimit.updatesPerMinute == 0)
            #expect(config.rateLimit.patchPerMinute == 0)
            #expect(config.cleanup == nil)
        }
    }

    @Test("Server config rejects invalid environment")
    func serverConfigRejectsInvalidEnvironment() throws {
        _ = try withServerEnvironment([:]) {
            #expect(throws: (any Error).self) {
                try ServerConfig.fromEnvironment()
            }
        }

        _ = try withServerEnvironment(
            [
                "CI_PUBLISH_TOKEN": publishToken,
                "SIGNING_KEYS_JSON": "[]",
                "SIGNING_ACTIVE_KEY_ID": signingKeyId
            ]
        ) {
            #expect(throws: (any Error).self) {
                try ServerConfig.fromEnvironment()
            }
        }

        _ = try withServerEnvironment(
            [
                "CI_PUBLISH_TOKEN": publishToken,
                "SIGNING_KEYS_JSON": makeSigningKeysJSON(),
                "SIGNING_ACTIVE_KEY_ID": signingKeyId,
                "METRICS_PORT": "abc"
            ]
        ) {
            #expect(throws: (any Error).self) {
                try ServerConfig.fromEnvironment()
            }
        }

        _ = try withServerEnvironment(
            [
                "CI_PUBLISH_TOKEN": publishToken,
                "SIGNING_KEYS_JSON": makeSigningKeysJSON(),
                "SIGNING_ACTIVE_KEY_ID": signingKeyId,
                "RATE_LIMIT_BACKEND": "redis"
            ]
        ) {
            #expect(throws: (any Error).self) {
                try ServerConfig.fromEnvironment()
            }
        }
    }
}
