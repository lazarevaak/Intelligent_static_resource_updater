//
//  ManifestStorage.swift
//  ResourceUpdateServer
//
//  Created by Karabelnikov Stepan on 01.02.2026.
//

import Vapor

actor ManifestStorage {

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

    func save(_ manifest: Manifest, appId: String, version: String, overwrite: Bool) async throws {
        try await publishManifest(manifest, appId: appId, version: version, overwrite: overwrite)
    }

    func publishManifest(_ manifest: Manifest, appId: String, version: String, overwrite: Bool) async throws {
        let appDirectory = appDirectoryURL(appId: appId)
        try ensureDirectoryExists(at: appDirectory)

        let fileURL = manifestURL(appId: appId, version: version)
        if FileManager.default.fileExists(atPath: fileURL.path), !overwrite {
            throw Abort(.conflict, reason: "manifest already exists")
        }

        let previousLatest = try? latestVersion(appId: appId)
        let previousManifest = previousLatest.flatMap { try? load(appId: appId, version: $0) }
        let data = try Self.makeEncoder().encode(manifest)

        let pendingURL = pendingManifestURL(appId: appId, version: version)
        var uploadedArtifactKeys: [String] = []

        do {
            // 1) stage manifest locally
            try data.write(to: pendingURL, options: .atomic)

            // 2) upload artifacts
            let manifestArtifactKey = artifactKey(appId: appId, category: "manifests", name: "\(version).json")
            try await artifactStorage.put(data, key: manifestArtifactKey, contentType: "application/json")
            uploadedArtifactKeys.append(manifestArtifactKey)

            if let fromVersion = previousLatest, let fromManifest = previousManifest {
                let patchMeta = buildPatchMeta(from: fromManifest, to: manifest, appId: appId, fromVersion: fromVersion, toVersion: version)
                let patchData = try Self.makeEncoder().encode(patchMeta)
                let patchArtifactKey = artifactKey(appId: appId, category: "patch-meta", name: "\(fromVersion)-\(version).json")
                try await artifactStorage.put(patchData, key: patchArtifactKey, contentType: "application/json")
                uploadedArtifactKeys.append(patchArtifactKey)

                let patchDocument = buildPatchDocument(from: fromManifest, to: manifest, appId: appId, fromVersion: fromVersion, toVersion: version)
                let patchDocumentData = try Self.makeEncoder().encode(patchDocument)
                let patchDocumentArtifactKey = artifactKey(appId: appId, category: "patches", name: "\(fromVersion)-\(version).json")
                try await artifactStorage.put(patchDocumentData, key: patchDocumentArtifactKey, contentType: "application/json")
                uploadedArtifactKeys.append(patchDocumentArtifactKey)
            }

            // 3) commit manifest version file
            try moveReplacing(source: pendingURL, destination: fileURL)

            // 4) switch latest pointer as final step
            try setLatest(appId: appId, version: version)
        } catch {
            try? FileManager.default.removeItem(at: pendingURL)
            for key in uploadedArtifactKeys.reversed() {
                try? await artifactStorage.delete(key: key)
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
        return buildPatchMeta(
            from: fromManifest,
            to: toManifest,
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion
        )
    }

    func buildPatchDocument(appId: String, fromVersion: String, toVersion: String) throws -> PatchDocument {
        let fromManifest = try load(appId: appId, version: fromVersion)
        let toManifest = try load(appId: appId, version: toVersion)
        return buildPatchDocument(
            from: fromManifest,
            to: toManifest,
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion
        )
    }

    private func buildPatchMeta(from fromManifest: Manifest, to toManifest: Manifest, appId: String, fromVersion: String, toVersion: String) -> PatchMeta {
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

        return PatchMeta(
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion,
            generatedAt: Date(),
            added: added,
            changed: changed,
            removed: removed
        )
    }

    private func buildPatchDocument(from fromManifest: Manifest, to toManifest: Manifest, appId: String, fromVersion: String, toVersion: String) -> PatchDocument {
        let fromByPath = Dictionary(uniqueKeysWithValues: fromManifest.resources.map { ($0.path, $0) })
        let toByPath = Dictionary(uniqueKeysWithValues: toManifest.resources.map { ($0.path, $0) })

        var operations: [PatchOperation] = []

        for (path, target) in toByPath {
            guard let source = fromByPath[path] else {
                operations.append(
                    PatchOperation(
                        op: "add",
                        path: path,
                        hash: target.hash,
                        size: target.size
                    )
                )
                continue
            }

            if source.hash != target.hash || source.size != target.size {
                operations.append(
                    PatchOperation(
                        op: "replace",
                        path: path,
                        hash: target.hash,
                        size: target.size
                    )
                )
            }
        }

        for path in fromByPath.keys where toByPath[path] == nil {
            operations.append(
                PatchOperation(
                    op: "remove",
                    path: path,
                    hash: nil,
                    size: nil
                )
            )
        }

        operations.sort { lhs, rhs in
            if lhs.path == rhs.path {
                return lhs.op < rhs.op
            }
            return lhs.path < rhs.path
        }

        return PatchDocument(
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion,
            generatedAt: Date(),
            operations: operations
        )
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
        appDirectoryURL(appId: appId)
            .appendingPathComponent("\(version).json")
    }

    private func latestPointerURL(appId: String) -> URL {
        appDirectoryURL(appId: appId)
            .appendingPathComponent("latest.txt")
    }

    private func pendingManifestURL(appId: String, version: String) -> URL {
        appDirectoryURL(appId: appId)
            .appendingPathComponent("\(version).json.pending")
    }

    private func appDirectoryURL(appId: String) -> URL {
        baseDirectoryURL.appendingPathComponent(appId, isDirectory: true)
    }

    private func ensureDirectoryExists(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func moveReplacing(source: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    private func artifactKey(appId: String, category: String, name: String) -> String {
        "apps/\(appId)/\(category)/\(name)"
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
