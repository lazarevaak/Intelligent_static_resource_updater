import Foundation
import Vapor

struct ServerConfig {
    let publishToken: String
    let artifactBackend: ArtifactBackend
    let s3: S3Config?

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
        return ServerConfig(
            publishToken: token,
            artifactBackend: backend,
            s3: s3Config
        )
    }
}
