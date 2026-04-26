import Foundation
import Vapor

struct ServerConfig {
    let publishToken: String
    let artifactBackend: ArtifactBackend
    let s3: S3Config?
    let signing: SigningConfig
    let metrics: MetricsConfig
    let rateLimit: RateLimitConfig
    let cleanup: CleanupConfig?

    enum ArtifactBackend: String {
        case local
        case s3
    }

    struct S3Config {
        let bucket: String
        let region: String
        let endpoint: String?
        let accessKeyId: String
        let secretAccessKey: String
        let usePathStyle: Bool
    }

    struct SigningConfig {
        struct Key: Decodable {
            let keyId: String
            let privateKeyBase64: String
            let createdAt: Date
        }

        let activeKeyId: String
        let keys: [Key]
    }

    struct MetricsConfig {
        let token: String?
        let allowlist: Set<String>
        let listener: ListenerConfig?

        struct ListenerConfig {
            let host: String
            let port: Int
        }

        var isEnabled: Bool {
            token != nil || !allowlist.isEmpty
        }
    }

    struct RateLimitConfig {
        enum Backend: String {
            case memory
            case sharedFile = "shared-file"
        }

        let backend: Backend
        let updatesPerMinute: Int
        let patchPerMinute: Int
        let sharedDirectory: String?
    }

    struct CleanupConfig {
        let intervalSeconds: Int
        let keepLast: Int
        let appIds: [String]?
    }

    static func fromEnvironment() throws -> ServerConfig {
        guard let token = Environment.get("CI_PUBLISH_TOKEN")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw Abort(.internalServerError, reason: "CI_PUBLISH_TOKEN is required")
        }
        let backendValue = Environment.get("ARTIFACT_BACKEND")?.lowercased()
        let backend = ArtifactBackend(rawValue: backendValue ?? "local") ?? .local
        let s3Config: S3Config?
        if backend == .s3 {
            let bucket = Environment.get("S3_BUCKET") ?? ""
            let region = Environment.get("S3_REGION") ?? "us-east-1"
            let accessKeyId = Environment.get("S3_ACCESS_KEY_ID") ?? ""
            let secretAccessKey = Environment.get("S3_SECRET_ACCESS_KEY") ?? ""
            let endpoint = Environment.get("S3_ENDPOINT")
            let usePathStyle = (Environment.get("S3_PATH_STYLE") ?? "true").lowercased() == "true"
            s3Config = S3Config(
                bucket: bucket,
                region: region,
                endpoint: endpoint,
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                usePathStyle: usePathStyle
            )
        } else {
            s3Config = nil
        }
        let signingConfig = try makeSigningConfig()
        let metricsConfig = try makeMetricsConfig()
        let rateLimitConfig = try makeRateLimitConfig()
        let cleanupConfig = makeCleanupConfig()
        return ServerConfig(
            publishToken: token,
            artifactBackend: backend,
            s3: s3Config,
            signing: signingConfig,
            metrics: metricsConfig,
            rateLimit: rateLimitConfig,
            cleanup: cleanupConfig
        )
    }

    private static func makeMetricsConfig() throws -> MetricsConfig {
        let token = Environment.get("METRICS_TOKEN")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = (token?.isEmpty == false) ? token : nil

        let listener: MetricsConfig.ListenerConfig?
        if let rawPort = Environment.get("METRICS_PORT")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawPort.isEmpty {
            guard let port = Int(rawPort), port > 0 else {
                throw Abort(.internalServerError, reason: "METRICS_PORT must be a positive integer")
            }
            let host = Environment.get("METRICS_BIND_HOST")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            listener = .init(host: (host?.isEmpty == false) ? host! : "127.0.0.1", port: port)
        } else {
            listener = nil
        }

        let allowlist = Set(
            (Environment.get("METRICS_ALLOWLIST") ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )

        return MetricsConfig(token: normalizedToken, allowlist: allowlist, listener: listener)
    }

    private static func makeRateLimitConfig() throws -> RateLimitConfig {
        let backendValue = Environment.get("RATE_LIMIT_BACKEND")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "memory"
        guard let backend = RateLimitConfig.Backend(rawValue: backendValue) else {
            throw Abort(.internalServerError, reason: "RATE_LIMIT_BACKEND must be one of: memory, shared-file")
        }
        let updatesPerMinute = max(Int(Environment.get("RATE_LIMIT_UPDATES_PER_MINUTE") ?? "") ?? 60, 0)
        let patchPerMinute = max(Int(Environment.get("RATE_LIMIT_PATCH_PER_MINUTE") ?? "") ?? 20, 0)
        let sharedDirectory = Environment.get("RATE_LIMIT_SHARED_DIR")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return RateLimitConfig(
            backend: backend,
            updatesPerMinute: updatesPerMinute,
            patchPerMinute: patchPerMinute,
            sharedDirectory: sharedDirectory?.isEmpty == false ? sharedDirectory : nil
        )
    }

    private static func makeCleanupConfig() -> CleanupConfig? {
        let intervalSeconds = Int(Environment.get("CLEANUP_INTERVAL_SECONDS") ?? "") ?? 0
        guard intervalSeconds > 0 else {
            return nil
        }

        let keepLast = max(Int(Environment.get("CLEANUP_KEEP_LAST") ?? "") ?? 3, 1)
        let appIds = (Environment.get("CLEANUP_APP_IDS") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return CleanupConfig(
            intervalSeconds: intervalSeconds,
            keepLast: keepLast,
            appIds: appIds.isEmpty ? nil : appIds
        )
    }

    private static func makeSigningConfig() throws -> SigningConfig {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let keysJSON = Environment.get("SIGNING_KEYS_JSON")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !keysJSON.isEmpty {
            let data = Data(keysJSON.utf8)
            let keys = try decoder.decode([SigningConfig.Key].self, from: data)
            if keys.isEmpty {
                throw Abort(.internalServerError, reason: "SIGNING_KEYS_JSON must contain at least one key")
            }
            let keyIds = Set(keys.map(\.keyId))
            if keyIds.count != keys.count {
                throw Abort(.internalServerError, reason: "SIGNING_KEYS_JSON contains duplicate keyId")
            }

            guard let activeKeyId = Environment.get("SIGNING_ACTIVE_KEY_ID")?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !activeKeyId.isEmpty
            else {
                throw Abort(.internalServerError, reason: "SIGNING_ACTIVE_KEY_ID is required when SIGNING_KEYS_JSON is set")
            }
            guard keyIds.contains(activeKeyId) else {
                throw Abort(.internalServerError, reason: "SIGNING_ACTIVE_KEY_ID must reference existing keyId in SIGNING_KEYS_JSON")
            }
            return SigningConfig(activeKeyId: activeKeyId, keys: keys)
        }

        // Backward-compatible single-key mode.
        guard let signingPrivateKey = Environment.get("SIGNING_PRIVATE_KEY_BASE64")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !signingPrivateKey.isEmpty
        else {
            throw Abort(.internalServerError, reason: "SIGNING_KEYS_JSON (preferred) or SIGNING_PRIVATE_KEY_BASE64 is required")
        }
        let signingKeyId = Environment.get("SIGNING_KEY_ID")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyId = signingKeyId?.isEmpty == false ? signingKeyId! : "main"
        let singleKey = SigningConfig.Key(
            keyId: keyId,
            privateKeyBase64: signingPrivateKey,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        return SigningConfig(activeKeyId: keyId, keys: [singleKey])
    }
}
