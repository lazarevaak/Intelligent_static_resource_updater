import Foundation
import Vapor
import SotoS3
import SotoCore

protocol ArtifactStorage: Sendable {
    func put(_ data: Data, key: String, contentType: String?) async throws
    func get(key: String) async throws -> Data?
    func delete(key: String) async throws
}

struct LocalArtifactStorage: ArtifactStorage {
    private let baseDirectoryURL: URL

    init(publicDirectory: String) {
        let publicURL = URL(fileURLWithPath: publicDirectory, isDirectory: true)
        self.baseDirectoryURL = publicURL.appendingPathComponent("artifacts", isDirectory: true)
    }

    func put(_ data: Data, key: String, contentType: String?) async throws {
        let safeKey = key.replacingOccurrences(of: "..", with: "_")
        let targetURL = baseDirectoryURL.appendingPathComponent(safeKey)
        let parent = targetURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try data.write(to: targetURL, options: .atomic)
    }

    func get(key: String) async throws -> Data? {
        let safeKey = key.replacingOccurrences(of: "..", with: "_")
        let targetURL = baseDirectoryURL.appendingPathComponent(safeKey)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return nil
        }
        return try Data(contentsOf: targetURL)
    }

    func delete(key: String) async throws {
        let safeKey = key.replacingOccurrences(of: "..", with: "_")
        let targetURL = baseDirectoryURL.appendingPathComponent(safeKey)
        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: targetURL)
    }
}

final class S3ArtifactStorage: ArtifactStorage, Sendable {
    private let bucket: String
    private let client: AWSClient
    private let s3: S3

    init(config: ServerConfig.S3Config) {
        self.bucket = config.bucket
        self.client = AWSClient(
            credentialProvider: .static(
                accessKeyId: config.accessKeyId,
                secretAccessKey: config.secretAccessKey
            )
        )

        let region = Region(rawValue: config.region)
        self.s3 = S3(
            client: client,
            region: region,
            endpoint: config.endpoint,
            timeout: .seconds(30),
            options: config.usePathStyle ? [] : .s3ForceVirtualHost
        )
    }

    func put(_ data: Data, key: String, contentType: String?) async throws {
        guard !bucket.isEmpty else {
            throw Abort(.internalServerError, reason: "S3 bucket is not configured")
        }
        let request = S3.PutObjectRequest(
            body: AWSHTTPBody(bytes: data),
            bucket: bucket,
            contentType: contentType,
            key: key
        )
        _ = try await s3.putObject(request)
    }

    func get(key: String) async throws -> Data? {
        guard !bucket.isEmpty else {
            throw Abort(.internalServerError, reason: "S3 bucket is not configured")
        }
        do {
            let output = try await s3.getObject(.init(bucket: bucket, key: key))
            var buffer = try await output.body.collect(upTo: .max)
            return buffer.readData(length: buffer.readableBytes) ?? Data()
        } catch let error as AWSResponseError where error.context?.responseCode == .notFound {
            return nil
        }
    }

    func delete(key: String) async throws {
        guard !bucket.isEmpty else {
            throw Abort(.internalServerError, reason: "S3 bucket is not configured")
        }
        let request = S3.DeleteObjectRequest(
            bucket: bucket,
            key: key
        )
        _ = try await s3.deleteObject(request)
    }

    func shutdown() async throws {
        try await client.shutdown()
    }
}

struct S3StorageLifecycle: LifecycleHandler {
    let storage: S3ArtifactStorage

    func shutdown(_ application: Application) {
        Task {
            do {
                try await storage.shutdown()
            } catch {
                application.logger.error("failed to shutdown S3 client", metadata: ["error": .string("\(error)")])
            }
        }
    }
}
