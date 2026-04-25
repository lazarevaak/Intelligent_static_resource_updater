import CryptoKit
import Vapor

actor ManifestStorage {

    enum PublishResult {
        case created
        case replayed
    }

    enum PatchUploadResult {
        case created
        case replayed
    }

    struct CleanupResult {
        let removedVersions: [String]
        let removedPatchArtifacts: Int
        let removedResourceBinaries: Int
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
            scope: .manifestPublish,
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
            let artifact = try await buildPatchArtifact(
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
                scope: .manifestPublish,
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

    func loadPatchArtifact(appId: String, fromVersion: String, toVersion: String) async throws -> (data: Data, sha256: String) {
        let url = patchArtifactURL(appId: appId, fromVersion: fromVersion, toVersion: toVersion)
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return (data, sha256(data))
        }

        let key = patchArtifactKey(appId: appId, fromVersion: fromVersion, toVersion: toVersion)
        if let data = try await artifactStorage.get(key: key) {
            try ensureDirectoryExists(at: patchDirectoryURL(appId: appId))
            let pending = pendingPatchArtifactURL(appId: appId, fromVersion: fromVersion, toVersion: toVersion)
            try data.write(to: pending, options: .atomic)
            try moveReplacing(source: pending, destination: url)
            return (data, sha256(data))
        }

        let fromManifest = try load(appId: appId, version: fromVersion)
        let toManifest = try load(appId: appId, version: toVersion)
        let artifact = try await buildPatchArtifact(
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

    func uploadPatchArtifact(
        appId: String,
        fromVersion: String,
        toVersion: String,
        requestId: String,
        payloadHash: String,
        expectedHash: String,
        expectedSize: Int?,
        data: Data
    ) async throws -> PatchUploadResult {
        _ = try load(appId: appId, version: fromVersion)
        _ = try load(appId: appId, version: toVersion)

        if let expectedSize, expectedSize != data.count {
            throw Abort(.badRequest, reason: "patch size mismatch")
        }
        let actualHash = sha256(data)
        if actualHash != expectedHash || payloadHash != actualHash {
            throw Abort(.badRequest, reason: "patch hash mismatch")
        }

        try ensureDirectoryExists(at: patchDirectoryURL(appId: appId))
        try ensureDirectoryExists(at: idempotencyDirectoryURL(appId: appId))

        let idempotency = try validateIdempotency(
            appId: appId,
            scope: .patchUpload,
            requestId: requestId,
            payloadHash: payloadHash
        )
        if idempotency == .replayed {
            return .replayed
        }

        let destination = patchArtifactURL(appId: appId, fromVersion: fromVersion, toVersion: toVersion)
        let pending = pendingPatchArtifactURL(appId: appId, fromVersion: fromVersion, toVersion: toVersion)
        let key = patchArtifactKey(appId: appId, fromVersion: fromVersion, toVersion: toVersion)

        do {
            try data.write(to: pending, options: .atomic)
            try await artifactStorage.put(data, key: key, contentType: "application/json")
            try moveReplacing(source: pending, destination: destination)
            try saveIdempotencyRecord(
                appId: appId,
                scope: .patchUpload,
                requestId: requestId,
                payloadHash: payloadHash,
                statusCode: Int(HTTPStatus.created.code)
            )
            return .created
        } catch {
            try? FileManager.default.removeItem(at: pending)
            throw error
        }
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

    func cleanup(appId: String, keepLast: Int) async throws -> CleanupResult {
        if keepLast < 1 {
            throw Abort(.badRequest, reason: "keepLast must be >= 1")
        }

        let versions = try listVersions(appId: appId)
        guard versions.count > keepLast else {
            return CleanupResult(removedVersions: [], removedPatchArtifacts: 0, removedResourceBinaries: 0)
        }

        var manifestsByVersion: [String: Manifest] = [:]
        for version in versions {
            manifestsByVersion[version] = try load(appId: appId, version: version)
        }

        let latest = try? latestVersion(appId: appId)
        let sortedByFreshness = manifestsByVersion.values.sorted {
            if $0.generatedAt == $1.generatedAt {
                return $0.version > $1.version
            }
            return $0.generatedAt > $1.generatedAt
        }

        var keep = Set(sortedByFreshness.prefix(keepLast).map(\.version))
        if let latest {
            keep.insert(latest)
        }

        let removedVersions = versions.filter { !keep.contains($0) }
        for version in removedVersions {
            let fileURL = manifestURL(appId: appId, version: version)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        }

        let removedPatchArtifacts = try await cleanupPatchArtifacts(appId: appId, removedVersions: Set(removedVersions))
        let removedResourceBinaries = try await cleanupResourceBinaries(
            appId: appId,
            keepVersions: keep,
            manifestsByVersion: manifestsByVersion
        )

        return CleanupResult(
            removedVersions: removedVersions,
            removedPatchArtifacts: removedPatchArtifacts,
            removedResourceBinaries: removedResourceBinaries
        )
    }

    private enum IdempotencyValidationResult {
        case fresh
        case replayed
    }

    private enum IdempotencyScope: String {
        case manifestPublish = "manifest"
        case patchUpload = "patch-upload"
    }

    private func validateIdempotency(
        appId: String,
        scope: IdempotencyScope,
        requestId: String,
        payloadHash: String
    ) throws -> IdempotencyValidationResult {
        let key = idempotencyRecordKey(scope: scope, requestId: requestId)
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

    private func saveIdempotencyRecord(
        appId: String,
        scope: IdempotencyScope,
        requestId: String,
        payloadHash: String,
        statusCode: Int
    ) throws {
        let key = idempotencyRecordKey(scope: scope, requestId: requestId)
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
    ) async throws -> PatchArtifact {
        let diff = buildDiff(fromManifest: fromManifest, toManifest: toManifest)
        var operations: [PatchOperation] = []

        operations.append(contentsOf: diff.removed.map {
            PatchOperation(op: "remove", path: $0, hash: nil, size: nil, dataBase64: nil, delta: nil)
        })
        for added in diff.added {
            let payload = try await loadResource(appId: appId, hash: added.hash)
            operations.append(
                PatchOperation(
                    op: "add",
                    path: added.path,
                    hash: added.hash,
                    size: added.size,
                    dataBase64: payload.base64EncodedString(),
                    delta: nil
                )
            )
        }
        for changed in diff.changed {
            let payload = try await loadResource(appId: appId, hash: changed.toHash)
            let sourcePayload = try? await loadResource(appId: appId, hash: changed.fromHash)
            let deltaPatch = makeSpliceDeltaPatch(
                sourceData: sourcePayload,
                sourceHash: changed.fromHash,
                sourceSize: changed.fromSize,
                targetData: payload,
                targetHash: changed.toHash
            )
            operations.append(
                PatchOperation(
                    op: "replace",
                    path: changed.path,
                    hash: changed.toHash,
                    size: changed.size,
                    dataBase64: nil,
                    delta: deltaPatch
                )
            )
        }

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
                        fromSize: source.size,
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

    private func makeSpliceDeltaPatch(
        sourceData: Data?,
        sourceHash: String,
        sourceSize: Int,
        targetData: Data,
        targetHash: String
    ) -> BinaryDeltaPatch {
        let source = sourceData ?? Data()
        let baseSize = sourceData == nil ? sourceSize : source.count
        let operation: BinaryDeltaOperation

        if sourceData == nil || source.isEmpty {
            operation = BinaryDeltaOperation(
                offset: 0,
                deleteLength: baseSize,
                dataBase64: targetData.base64EncodedString()
            )
        } else {
            let sourceBytes = [UInt8](source)
            let targetBytes = [UInt8](targetData)

            var prefix = 0
            while prefix < sourceBytes.count, prefix < targetBytes.count, sourceBytes[prefix] == targetBytes[prefix] {
                prefix += 1
            }

            var suffix = 0
            while suffix < (sourceBytes.count - prefix),
                  suffix < (targetBytes.count - prefix),
                  sourceBytes[sourceBytes.count - 1 - suffix] == targetBytes[targetBytes.count - 1 - suffix] {
                suffix += 1
            }

            let sourceEnd = sourceBytes.count - suffix
            let targetEnd = targetBytes.count - suffix
            let middle = Data(targetBytes[prefix..<targetEnd])

            operation = BinaryDeltaOperation(
                offset: prefix,
                deleteLength: sourceEnd - prefix,
                dataBase64: middle.base64EncodedString()
            )
        }

        return BinaryDeltaPatch(
            algorithm: "splice-v1",
            baseHash: sourceHash,
            baseSize: baseSize,
            targetHash: targetHash,
            targetSize: targetData.count,
            operations: [operation]
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func sanitizedRequestId(_ requestId: String) -> String {
        requestId.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    }

    private func idempotencyRecordKey(scope: IdempotencyScope, requestId: String) -> String {
        "\(scope.rawValue)-\(sanitizedRequestId(requestId))"
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

    private func patchArtifactKey(appId: String, fromVersion: String, toVersion: String) -> String {
        "apps/\(appId)/patches/\(fromVersion)-\(toVersion).patch.json"
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

    private func cleanupPatchArtifacts(appId: String, removedVersions: Set<String>) async throws -> Int {
        let patchesDirectory = patchDirectoryURL(appId: appId)
        guard FileManager.default.fileExists(atPath: patchesDirectory.path) else {
            return 0
        }
        let files = try FileManager.default.contentsOfDirectory(at: patchesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".patch.json") }

        var removed = 0
        for file in files {
            let name = file.lastPathComponent.replacingOccurrences(of: ".patch.json", with: "")
            let components = name.split(separator: "-", maxSplits: 1).map(String.init)
            guard components.count == 2 else { continue }
            let fromVersion = components[0]
            let toVersion = components[1]
            guard removedVersions.contains(fromVersion) || removedVersions.contains(toVersion) else {
                continue
            }
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            try? await artifactStorage.delete(key: patchArtifactKey(appId: appId, fromVersion: fromVersion, toVersion: toVersion))
            removed += 1
        }

        return removed
    }

    private func cleanupResourceBinaries(
        appId: String,
        keepVersions: Set<String>,
        manifestsByVersion: [String: Manifest]
    ) async throws -> Int {
        let resourceDirectory = resourceDirectoryURL(appId: appId)
        guard FileManager.default.fileExists(atPath: resourceDirectory.path) else {
            return 0
        }

        let keepHashes = Set(
            keepVersions
                .compactMap { manifestsByVersion[$0] }
                .flatMap { $0.resources.map(\.hash) }
        )

        let files = try FileManager.default.contentsOfDirectory(at: resourceDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "bin" }

        var removed = 0
        for file in files {
            let hash = file.deletingPathExtension().lastPathComponent
            guard !keepHashes.contains(hash) else { continue }
            try FileManager.default.removeItem(at: file)
            try? await artifactStorage.delete(key: "apps/\(appId)/resources/\(hash).bin")
            removed += 1
        }
        return removed
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
