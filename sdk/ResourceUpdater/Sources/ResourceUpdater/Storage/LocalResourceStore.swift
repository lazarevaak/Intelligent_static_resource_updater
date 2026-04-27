//
//  LocalResourceStore.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 26.01.2026.
//

import Foundation

public final class LocalResourceStore: @unchecked Sendable {
    private struct State: Codable {
        let currentVersion: String?
        let manifest: Manifest?
    }

    private let rootDirectory: URL
    private let resourcesDirectory: URL
    private let stateFileURL: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        self.resourcesDirectory = rootDirectory.appendingPathComponent("resources", isDirectory: true)
        self.stateFileURL = rootDirectory.appendingPathComponent("state.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func currentVersion() -> String? {
        loadState().currentVersion
    }

    func isUpdateNeeded(_ manifest: Manifest) -> Bool {
        manifest.version != currentVersion()
    }

    func save(manifest: Manifest) throws {
        try persist(state: State(currentVersion: manifest.version, manifest: manifest))
    }

    func applyManifest(
        _ manifest: Manifest,
        resourceProvider: (String) async throws -> Data
    ) async throws {
        try ensureBaseDirectories()
        let backupURL = try createBackup()

        do {
            try removeContents(of: resourcesDirectory)

            for resource in manifest.resources {
                let data = try await resourceProvider(resource.hash)
                try validate(data: data, expectedHash: resource.hash, expectedSize: resource.size)
                try write(data: data, forRelativePath: resource.path)
            }

            try validateInstalledResources(match: manifest)
            try persist(state: State(currentVersion: manifest.version, manifest: manifest))
            try removeBackup(at: backupURL)
        } catch {
            try restoreBackup(from: backupURL)
            throw error
        }
    }

    func applyPatch(
        _ patch: PatchArtifact,
        targetManifest: Manifest
    ) throws {
        try ensureBaseDirectories()
        let backupURL = try createBackup()

        do {
            for operation in patch.operations {
                try apply(operation: operation)
            }

            try pruneUnexpectedResources(keeping: Set(targetManifest.resources.map { normalizedRelativePath($0.path) }))
            try validateInstalledResources(match: targetManifest)
            try persist(state: State(currentVersion: targetManifest.version, manifest: targetManifest))
            try removeBackup(at: backupURL)
        } catch {
            try restoreBackup(from: backupURL)
            throw error
        }
    }

    private func loadState() -> State {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? decoder.decode(State.self, from: data) else {
            return State(currentVersion: nil, manifest: nil)
        }
        return state
    }

    private func persist(state: State) throws {
        try ensureBaseDirectories()
        let data = try encoder.encode(state)
        try data.write(to: stateFileURL, options: .atomic)
    }

    private func ensureBaseDirectories() throws {
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try FileManager.default.createDirectory(
            at: resourcesDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func createBackup() throws -> URL {
        let backupURL = rootDirectory.appendingPathComponent("resources.backup", isDirectory: true)
        try? FileManager.default.removeItem(at: backupURL)
        if FileManager.default.fileExists(atPath: resourcesDirectory.path) {
            try FileManager.default.copyItem(at: resourcesDirectory, to: backupURL)
        } else {
            try FileManager.default.createDirectory(
                at: backupURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        return backupURL
    }

    private func restoreBackup(from backupURL: URL) throws {
        try? FileManager.default.removeItem(at: resourcesDirectory)
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.copyItem(at: backupURL, to: resourcesDirectory)
            try? FileManager.default.removeItem(at: backupURL)
        } else {
            try FileManager.default.createDirectory(
                at: resourcesDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    private func removeBackup(at backupURL: URL) throws {
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
    }

    private func removeContents(of directory: URL) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
    }

    private func apply(operation: PatchOperation) throws {
        switch operation.op {
        case "remove":
            try removeResource(at: operation.path)
        case "add":
            let data = try requireInlineData(for: operation)
            let hash = try requireHash(for: operation)
            let size = try requireSize(for: operation)
            try validate(data: data, expectedHash: hash, expectedSize: size)
            try write(data: data, forRelativePath: operation.path)
        case "replace":
            try replaceResource(using: operation)
        default:
            throw ResourceUpdaterError.invalidPatchOperation(operation.op)
        }
    }

    private func replaceResource(using operation: PatchOperation) throws {
        let hash = try requireHash(for: operation)
        let size = try requireSize(for: operation)
        let targetURL = try resolvedResourceURL(forRelativePath: operation.path)

        if let inlineData = operation.dataBase64 {
            guard let data = Data(base64Encoded: inlineData) else {
                throw ResourceUpdaterError.invalidPatchOperation("invalid base64 data")
            }
            try validate(data: data, expectedHash: hash, expectedSize: size)
            try write(data: data, to: targetURL)
            return
        }

        guard let delta = operation.delta else {
            throw ResourceUpdaterError.invalidPatchOperation("replace without payload")
        }
        guard delta.algorithm == "splice-v1" else {
            throw ResourceUpdaterError.unsupportedDeltaAlgorithm(delta.algorithm)
        }

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            throw ResourceUpdaterError.resourceNotFound(operation.path)
        }

        let baseData = try Data(contentsOf: targetURL)
        try validate(data: baseData, expectedHash: delta.baseHash, expectedSize: delta.baseSize)

        var result = baseData
        for splice in delta.operations.sorted(by: { $0.offset > $1.offset }) {
            guard splice.offset >= 0, splice.deleteLength >= 0 else {
                throw ResourceUpdaterError.invalidPatchOperation("negative splice bounds")
            }
            guard splice.offset + splice.deleteLength <= result.count else {
                throw ResourceUpdaterError.invalidPatchOperation("splice out of range")
            }
            guard let replacement = Data(base64Encoded: splice.dataBase64) else {
                throw ResourceUpdaterError.invalidPatchOperation("invalid splice base64")
            }

            let start = result.startIndex.advanced(by: splice.offset)
            let end = start.advanced(by: splice.deleteLength)
            result.replaceSubrange(start..<end, with: replacement)
        }

        try validate(data: result, expectedHash: delta.targetHash, expectedSize: delta.targetSize)
        try validate(data: result, expectedHash: hash, expectedSize: size)
        try write(data: result, to: targetURL)
    }

    private func requireInlineData(for operation: PatchOperation) throws -> Data {
        guard let base64 = operation.dataBase64,
              let data = Data(base64Encoded: base64) else {
            throw ResourceUpdaterError.invalidPatchOperation("missing inline data")
        }
        return data
    }

    private func requireHash(for operation: PatchOperation) throws -> String {
        guard let hash = operation.hash else {
            throw ResourceUpdaterError.invalidPatchOperation("missing hash")
        }
        return hash
    }

    private func requireSize(for operation: PatchOperation) throws -> Int {
        guard let size = operation.size else {
            throw ResourceUpdaterError.invalidPatchOperation("missing size")
        }
        return size
    }

    private func removeResource(at relativePath: String) throws {
        let url = try resolvedResourceURL(forRelativePath: relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            try removeEmptyParentDirectories(startingAt: url.deletingLastPathComponent())
        }
    }

    private func write(data: Data, forRelativePath relativePath: String) throws {
        let url = try resolvedResourceURL(forRelativePath: relativePath)
        try write(data: data, to: url)
    }

    private func write(data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: .atomic)
    }

    private func validate(data: Data, expectedHash: String, expectedSize: Int) throws {
        let actualHash = CryptoSupport.sha256Hex(data)
        if actualHash != expectedHash {
            throw ResourceUpdaterError.hashMismatch(expected: expectedHash, actual: actualHash)
        }
        if data.count != expectedSize {
            throw ResourceUpdaterError.sizeMismatch(expected: expectedSize, actual: data.count)
        }
    }

    private func validateInstalledResources(match manifest: Manifest) throws {
        for resource in manifest.resources {
            let url = try resolvedResourceURL(forRelativePath: resource.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ResourceUpdaterError.resourceNotFound(resource.path)
            }
            let data = try Data(contentsOf: url)
            try validate(data: data, expectedHash: resource.hash, expectedSize: resource.size)
        }

    }

    private func pruneUnexpectedResources(keeping expectedPaths: Set<String>) throws {
        let actualPaths = try collectStoredResourcePaths()
        for extraPath in actualPaths.subtracting(expectedPaths) {
            try removeResource(at: extraPath)
        }
    }

    private func collectStoredResourcePaths() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: resourcesDirectory.path) else {
            return []
        }

        let enumerator = FileManager.default.enumerator(
            at: resourcesDirectory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )

        var paths = Set<String>()
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = fileURL.path.replacingOccurrences(
                of: resourcesDirectory.path + "/",
                with: ""
            )
            paths.insert(normalizedRelativePath(relative))
        }
        return paths
    }

    private func resolvedResourceURL(forRelativePath relativePath: String) throws -> URL {
        let normalized = normalizedRelativePath(relativePath)
        let url = resourcesDirectory.appendingPathComponent(normalized)
        let standardized = url.standardizedFileURL
        let basePath = resourcesDirectory.standardizedFileURL.path + "/"
        guard standardized.path.hasPrefix(basePath) else {
            throw ResourceUpdaterError.invalidResourcePath(relativePath)
        }
        return standardized
    }

    private func normalizedRelativePath(_ relativePath: String) -> String {
        relativePath.split(separator: "/").joined(separator: "/")
    }

    private func removeEmptyParentDirectories(startingAt directory: URL) throws {
        var current = directory
        let base = resourcesDirectory.standardizedFileURL.path

        while current.standardizedFileURL.path.hasPrefix(base),
              current.standardizedFileURL.path != base {
            let contents = try FileManager.default.contentsOfDirectory(atPath: current.path)
            if !contents.isEmpty {
                return
            }
            try FileManager.default.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }
}
