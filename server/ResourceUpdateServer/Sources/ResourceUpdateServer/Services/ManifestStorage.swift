import CryptoKit
import Vapor

actor ManifestStorage {

    enum PublishResult {
        case created
        case replayed
    }

    private struct IdempotencyRecord: Codable {
        let requestId: String
        let payloadHash: String
        let statusCode: Int
        let createdAt: Date
    }

    struct ResourceUploadResult {
        let created: Bool
        let hash: String
        let size: Int
    }

    private let baseDirectoryURL: URL
    private let artifactStorage: any ArtifactStorage

    init(publicDirectory: String, artifactStorage: any ArtifactStorage) {
        let publicURL = URL(fileURLWithPath: publicDirectory, isDirectory: true)
        self.baseDirectoryURL = publicURL.appendingPathComponent("manifests", isDirectory: true)
        self.artifactStorage = artifactStorage
    }

    func load(appId: String, version: String) throws -> Manifest {
        let fileURL = manifestURL(appId: appId, version: version)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw Abort(.notFound, reason: "manifest not found")
        }
        let data = try Data(contentsOf: fileURL)
        return try Self.makeDecoder().decode(Manifest.self, from: data)
    }

    func loadLatest(appId: String) throws -> Manifest {
        let version = try latestVersion(appId: appId)
        return try load(appId: appId, version: version)
    }

    func save(
        _ manifest: Manifest,
        appId: String,
        version: String,
        overwrite: Bool,
        requestId: String,
        payloadHash: String
    ) async throws -> PublishResult {
        let appDirectory = appDirectoryURL(appId: appId)
        try ensureDirectoryExists(at: appDirectory)
        try ensureDirectoryExists(at: patchDirectoryURL(appId: appId))
        try ensureDirectoryExists(at: idempotencyDirectoryURL(appId: appId))

        let idempotency = try validateIdempotency(
            appId: appId,
            requestId: requestId,
            payloadHash: payloadHash
        )
        if idempotency == .replayed {
            return .replayed
        }

        let fileURL = manifestURL(appId: appId, version: version)
        if FileManager.default.fileExists(atPath: fileURL.path), !overwrite {
            throw Abort(.conflict, reason: "manifest already exists")
        }

        let previousLatest = try? latestVersion(appId: appId)
        let previousManifest = previousLatest.flatMap { try? load(appId: appId, version: $0) }

        let manifestData = try Self.makeEncoder().encode(manifest)
        let pendingManifest = pendingManifestURL(appId: appId, version: version)

        var pendingPatchURL: URL?
        var patchDataForUpload: Data?
        var patchArtifactKey: String?
        var committedManifest = false
        var committedPatchURL: URL?
        var latestWasUpdated = false
        if let fromVersion = previousLatest, let fromManifest = previousManifest {
            let artifact = buildPatchArtifact(
                appId: appId,
                fromVersion: fromVersion,
                toVersion: version,
                fromManifest: fromManifest,
                toManifest: manifest
            )
            let patchData = try Self.makeEncoder().encode(artifact)
            let pendingPatch = pendingPatchArtifactURL(appId: appId, fromVersion: fromVersion, toVersion: version)
            try patchData.write(to: pendingPatch, options: Data.WritingOptions.atomic)
            pendingPatchURL = pendingPatch
            patchDataForUpload = patchData
            patchArtifactKey = "apps/\(appId)/patches/\(fromVersion)-\(version).patch.json"
        }

        do {
            try manifestData.write(to: pendingManifest, options: .atomic)

            if let patchDataForUpload, let patchArtifactKey {
                try await artifactStorage.put(
                    patchDataForUpload,
                    key: patchArtifactKey,
                    contentType: "application/json"
                )
            }

            try moveReplacing(source: pendingManifest, destination: fileURL)
            committedManifest = true

            if let fromVersion = previousLatest, let pendingPatchURL {
                let destinationPatch = patchArtifactURL(appId: appId, fromVersion: fromVersion, toVersion: version)
                try moveReplacing(source: pendingPatchURL, destination: destinationPatch)
                committedPatchURL = destinationPatch
            }

            try setLatest(appId: appId, version: version)
            latestWasUpdated = true
            try saveIdempotencyRecord(
                appId: appId,
                requestId: requestId,
                payloadHash: payloadHash,
                statusCode: Int(HTTPStatus.created.code)
            )
            return .created
        } catch {
            try? FileManager.default.removeItem(at: pendingManifest)
            if let pendingPatchURL {
                try? FileManager.default.removeItem(at: pendingPatchURL)
            }
            if committedManifest {
                try? FileManager.default.removeItem(at: fileURL)
            }
            if let committedPatchURL {
                try? FileManager.default.removeItem(at: committedPatchURL)
            }
            if latestWasUpdated {
                if let previousLatest {
                    try? setLatest(appId: appId, version: previousLatest)
                } else {
                    try? FileManager.default.removeItem(at: latestPointerURL(appId: appId))
                }
            }
            if let patchArtifactKey {
                try? await artifactStorage.delete(key: patchArtifactKey)
            }
            throw error
        }
    }

    func listVersions(appId: String) throws -> [String] {
        let appDirectory = appDirectoryURL(appId: appId)
        guard FileManager.default.fileExists(atPath: appDirectory.path) else {
            return []
        }

        let items = try FileManager.default.contentsOfDirectory(
            at: appDirectory,
            includingPropertiesForKeys: nil
        )

        return items
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    func buildPatchMeta(appId: String, fromVersion: String, toVersion: String) throws -> PatchMeta {
        let fromManifest = try load(appId: appId, version: fromVersion)
        let toManifest = try load(appId: appId, version: toVersion)
        let diff = buildDiff(fromManifest: fromManifest, toManifest: toManifest)

        return PatchMeta(
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion,
            generatedAt: Date(),
            added: diff.added,
            changed: diff.changed,
            removed: diff.removed
        )
    }

    func loadPatchArtifact(appId: String, fromVersion: String, toVersion: String) throws -> (data: Data, sha256: String) {
        let url = patchArtifactURL(appId: appId, fromVersion: fromVersion, toVersion: toVersion)
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return (data, sha256(data))
        }

        let fromManifest = try load(appId: appId, version: fromVersion)
        let toManifest = try load(appId: appId, version: toVersion)
        let artifact = buildPatchArtifact(
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion,
            fromManifest: fromManifest,
            toManifest: toManifest
        )
        let data = try Self.makeEncoder().encode(artifact)
        try data.write(to: url, options: Data.WritingOptions.atomic)
        return (data, sha256(data))
    }

    func uploadResource(
        appId: String,
        path: String,
        expectedHash: String,
        expectedSize: Int?,
        data: Data
    ) async throws -> ResourceUploadResult {
        try ensureDirectoryExists(at: resourceDirectoryURL(appId: appId))

        if let expectedSize, expectedSize != data.count {
            throw Abort(.badRequest, reason: "resource size mismatch")
        }

        let actualHash = sha256(data)
        if actualHash != expectedHash {
            throw Abort(.badRequest, reason: "resource hash mismatch")
        }

        let destination = resourceFileURL(appId: appId, hash: expectedHash)
        let existed = FileManager.default.fileExists(atPath: destination.path)
        if !existed {
            let pending = destination.deletingPathExtension().appendingPathExtension("bin.pending")
            try data.write(to: pending, options: .atomic)
            try moveReplacing(source: pending, destination: destination)
        }

        let key = "apps/\(appId)/resources/\(expectedHash).bin"
        try await artifactStorage.put(data, key: key, contentType: "application/octet-stream")

        // Keep lightweight path->hash mapping for diagnostics and future SDK flows.
        let mappingURL = resourcePathMappingURL(appId: appId, path: path)
        try ensureDirectoryExists(at: mappingURL.deletingLastPathComponent())
        try Data(expectedHash.utf8).write(to: mappingURL, options: .atomic)

        return ResourceUploadResult(
            created: !existed,
            hash: expectedHash,
            size: data.count
        )
    }

    func loadResource(appId: String, hash: String) async throws -> Data {
        let fileURL = resourceFileURL(appId: appId, hash: hash)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try Data(contentsOf: fileURL)
        }

        let key = "apps/\(appId)/resources/\(hash).bin"
        if let data = try await artifactStorage.get(key: key) {
            try ensureDirectoryExists(at: resourceDirectoryURL(appId: appId))
            let pending = fileURL.deletingPathExtension().appendingPathExtension("bin.pending")
            try data.write(to: pending, options: .atomic)
            try moveReplacing(source: pending, destination: fileURL)
            return data
        }

        throw Abort(.notFound, reason: "resource not found")
    }

    private enum IdempotencyValidationResult {
        case fresh
        case replayed
    }

    private func validateIdempotency(appId: String, requestId: String, payloadHash: String) throws -> IdempotencyValidationResult {
        let key = sanitizedRequestId(requestId)
        let recordURL = idempotencyDirectoryURL(appId: appId).appendingPathComponent("\(key).json")
        guard FileManager.default.fileExists(atPath: recordURL.path) else {
            return .fresh
        }
        let data = try Data(contentsOf: recordURL)
        let record = try Self.makeDecoder().decode(IdempotencyRecord.self, from: data)
        if record.payloadHash != payloadHash {
            throw Abort(.conflict, reason: "requestId already used with different payload")
        }
        return .replayed
    }

    private func saveIdempotencyRecord(appId: String, requestId: String, payloadHash: String, statusCode: Int) throws {
        let key = sanitizedRequestId(requestId)
        let recordURL = idempotencyDirectoryURL(appId: appId).appendingPathComponent("\(key).json")
        let record = IdempotencyRecord(
            requestId: requestId,
            payloadHash: payloadHash,
            statusCode: statusCode,
            createdAt: Date()
        )
        let data = try Self.makeEncoder().encode(record)
        try data.write(to: recordURL, options: .atomic)
    }

    private func buildPatchArtifact(
        appId: String,
        fromVersion: String,
        toVersion: String,
        fromManifest: Manifest,
        toManifest: Manifest
    ) -> PatchArtifact {
        let diff = buildDiff(fromManifest: fromManifest, toManifest: toManifest)
        var operations: [PatchOperation] = []

        operations.append(contentsOf: diff.removed.map {
            PatchOperation(op: "remove", path: $0, hash: nil, size: nil)
        })
        operations.append(contentsOf: diff.added.map {
            PatchOperation(op: "add", path: $0.path, hash: $0.hash, size: $0.size)
        })
        operations.append(contentsOf: diff.changed.map {
            PatchOperation(op: "replace", path: $0.path, hash: $0.toHash, size: $0.size)
        })

        return PatchArtifact(
            schemaVersion: toManifest.schemaVersion,
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion,
            generatedAt: Date(),
            operations: operations
        )
    }

    private func buildDiff(fromManifest: Manifest, toManifest: Manifest) -> (added: [ResourceEntry], changed: [ChangedResource], removed: [String]) {
        let fromByPath = Dictionary(uniqueKeysWithValues: fromManifest.resources.map { ($0.path, $0) })
        let toByPath = Dictionary(uniqueKeysWithValues: toManifest.resources.map { ($0.path, $0) })

        var added: [ResourceEntry] = []
        var changed: [ChangedResource] = []
        var removed: [String] = []

        for (path, target) in toByPath {
            guard let source = fromByPath[path] else {
                added.append(target)
                continue
            }
            if source.hash != target.hash || source.size != target.size {
                changed.append(
                    ChangedResource(
                        path: path,
                        fromHash: source.hash,
                        toHash: target.hash,
                        size: target.size
                    )
                )
            }
        }

        for path in fromByPath.keys where toByPath[path] == nil {
            removed.append(path)
        }

        added.sort { $0.path < $1.path }
        changed.sort { $0.path < $1.path }
        removed.sort()
        return (added, changed, removed)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sanitizedRequestId(_ requestId: String) -> String {
        requestId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    }

    private func latestVersion(appId: String) throws -> String {
        let pointerURL = latestPointerURL(appId: appId)
        guard FileManager.default.fileExists(atPath: pointerURL.path) else {
            throw Abort(.notFound, reason: "latest manifest not set")
        }
        let data = try Data(contentsOf: pointerURL)
        let version = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if version.isEmpty {
            throw Abort(.internalServerError, reason: "latest manifest pointer is empty")
        }
        return version
    }

    private func setLatest(appId: String, version: String) throws {
        let pointerURL = latestPointerURL(appId: appId)
        let data = Data(version.utf8)
        try data.write(to: pointerURL, options: .atomic)
    }

    private func manifestURL(appId: String, version: String) -> URL {
        appDirectoryURL(appId: appId).appendingPathComponent("\(version).json")
    }

    private func pendingManifestURL(appId: String, version: String) -> URL {
        appDirectoryURL(appId: appId).appendingPathComponent("\(version).json.pending")
    }

    private func latestPointerURL(appId: String) -> URL {
        appDirectoryURL(appId: appId).appendingPathComponent("latest.txt")
    }

    private func appDirectoryURL(appId: String) -> URL {
        baseDirectoryURL.appendingPathComponent(appId, isDirectory: true)
    }

    private func patchDirectoryURL(appId: String) -> URL {
        baseDirectoryURL.appendingPathComponent(appId, isDirectory: true).appendingPathComponent("patches", isDirectory: true)
    }

    private func patchArtifactURL(appId: String, fromVersion: String, toVersion: String) -> URL {
        patchDirectoryURL(appId: appId).appendingPathComponent("\(fromVersion)-\(toVersion).patch.json")
    }

    private func pendingPatchArtifactURL(appId: String, fromVersion: String, toVersion: String) -> URL {
        patchDirectoryURL(appId: appId).appendingPathComponent("\(fromVersion)-\(toVersion).patch.json.pending")
    }

    private func idempotencyDirectoryURL(appId: String) -> URL {
        baseDirectoryURL.appendingPathComponent(appId, isDirectory: true).appendingPathComponent("idempotency", isDirectory: true)
    }

    private func resourceDirectoryURL(appId: String) -> URL {
        baseDirectoryURL.appendingPathComponent(appId, isDirectory: true).appendingPathComponent("resources", isDirectory: true)
    }

    private func resourceFileURL(appId: String, hash: String) -> URL {
        resourceDirectoryURL(appId: appId).appendingPathComponent("\(hash).bin")
    }

    private func resourcePathMappingURL(appId: String, path: String) -> URL {
        let escapedPath = path
            .replacingOccurrences(of: "..", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return resourceDirectoryURL(appId: appId)
            .appendingPathComponent("path-map", isDirectory: true)
            .appendingPathComponent("\(escapedPath).txt")
    }

    private func ensureDirectoryExists(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }

    private func moveReplacing(source: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
