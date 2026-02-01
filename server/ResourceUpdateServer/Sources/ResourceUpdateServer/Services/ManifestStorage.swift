//
//  ManifestStorage.swift
//  ResourceUpdateServer
//
//  Created by Karabelnikov Stepan on 01.02.2026.
//

import Vapor

actor ManifestStorage {

    private let baseDirectoryURL: URL

    init(publicDirectory: String) {
        let publicURL = URL(fileURLWithPath: publicDirectory, isDirectory: true)
        self.baseDirectoryURL = publicURL.appendingPathComponent("manifests", isDirectory: true)
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

    func save(_ manifest: Manifest, appId: String, version: String, overwrite: Bool) throws {
        let appDirectory = appDirectoryURL(appId: appId)
        try ensureDirectoryExists(at: appDirectory)

        let fileURL = manifestURL(appId: appId, version: version)
        if FileManager.default.fileExists(atPath: fileURL.path), !overwrite {
            throw Abort(.conflict, reason: "manifest already exists")
        }

        let data = try Self.makeEncoder().encode(manifest)
        try data.write(to: fileURL, options: .atomic)
        try setLatest(appId: appId, version: version)
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
