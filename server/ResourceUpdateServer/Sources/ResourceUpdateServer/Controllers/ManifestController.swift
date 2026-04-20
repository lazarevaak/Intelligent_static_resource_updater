//
//  ManifestController.swift
//  ResourceUpdateServer
//
//  Created by Karabelnikov Stepan on 01.02.2026.
//

import Vapor

struct ManifestController {

    private let storage: ManifestStorage

    init(publicDirectory: String) {
        self.storage = ManifestStorage(publicDirectory: publicDirectory)
    }

    func getLatestManifest(req: Request) async throws -> Manifest {
        let appId = try requireParam(req, "appId")
        try validateIdentifier(appId, name: "appId")
        return try await storage.loadLatest(appId: appId)
    }

    func getManifest(req: Request) async throws -> Manifest {
        let appId = try requireParam(req, "appId")
        let version = try requireParam(req, "version")
        try validateIdentifier(appId, name: "appId")
        try validateIdentifier(version, name: "version")
        return try await storage.load(appId: appId, version: version)
    }

    func listManifestVersions(req: Request) async throws -> [String] {
        let appId = try requireParam(req, "appId")
        try validateIdentifier(appId, name: "appId")
        return try await storage.listVersions(appId: appId)
    }

    func updateManifest(req: Request) async throws -> HTTPStatus {
        let appId = try requireParam(req, "appId")
        let version = try requireParam(req, "version")
        try validateIdentifier(appId, name: "appId")
        try validateIdentifier(version, name: "version")

        let manifest = try req.content.decode(Manifest.self)
        try validate(manifest)
        if manifest.version != version {
            throw Abort(.badRequest, reason: "manifest.version must match URL version")
        }
        try await storage.save(manifest, appId: appId, version: version, overwrite: false)
        return .created
    }

    func getPatchMeta(req: Request) async throws -> PatchMeta {
        let appId = try requireParam(req, "appId")
        let fromVersion = try requireParam(req, "fromVersion")
        let toVersion = try requireParam(req, "toVersion")
        try validateIdentifier(appId, name: "appId")
        try validateIdentifier(fromVersion, name: "fromVersion")
        try validateIdentifier(toVersion, name: "toVersion")

        return try await storage.buildPatchMeta(
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion
        )
    }

    private func validate(_ manifest: Manifest) throws {
        if manifest.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw Abort(.badRequest, reason: "manifest.version is required")
        }

        var seenPaths = Set<String>()
        for entry in manifest.resources {
            let path = entry.path.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty {
                throw Abort(.badRequest, reason: "resource.path is required")
            }
            try validateResourcePath(path)
            if !seenPaths.insert(path).inserted {
                throw Abort(.badRequest, reason: "duplicate resource path: \(path)")
            }
            if entry.hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw Abort(.badRequest, reason: "resource.hash is required")
            }
            try validateHash(entry.hash)
            if entry.size < 0 {
                throw Abort(.badRequest, reason: "resource.size must be >= 0")
            }
        }
    }

    private func validateIdentifier(_ value: String, name: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw Abort(.badRequest, reason: "\(name) is required")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw Abort(.badRequest, reason: "\(name) contains invalid characters")
        }
    }

    private func validateResourcePath(_ path: String) throws {
        if path.hasPrefix("/") || path.hasPrefix("\\") {
            throw Abort(.badRequest, reason: "resource.path must be relative")
        }
        if path.contains("..") {
            throw Abort(.badRequest, reason: "resource.path must not contain '..'")
        }
    }

    private func validateHash(_ hash: String) throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 8 || trimmed.count > 128 {
            throw Abort(.badRequest, reason: "resource.hash has invalid length")
        }
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw Abort(.badRequest, reason: "resource.hash contains invalid characters")
        }
    }

    private func requireParam(_ req: Request, _ name: String) throws -> String {
        guard let value = req.parameters.get(name) else {
            throw Abort(.badRequest, reason: "missing parameter: \(name)")
        }
        return value
    }
}
