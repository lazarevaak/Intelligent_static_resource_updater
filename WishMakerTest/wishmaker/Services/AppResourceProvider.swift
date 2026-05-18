//
//  AppResourceProvider.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 28.04.2026.

import Foundation

enum AppResourcePath {
    static let appConfiguration = "app-config/app-config.json"
    static let theme = "theme/theme.json"
    static let locations = "locations/locations.json"
    static let vehicles = "vehicles/vehicles.json"
    static let avatarOptions = "profile/avatar-options.json"
    static let defaultChargingVehicleImage = "images/charging-vehicle.png"

    static func localization(_ languageCode: String) -> String {
        "localization/\(languageCode).json"
    }
}

enum AppResourceStorage {
    static let rootDirectory: URL = {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDirectory.appendingPathComponent("wishmaker-resource-updater", isDirectory: true)
    }()

    static let updatedResourcesDirectory = rootDirectory.appendingPathComponent("resources", isDirectory: true)
}

final class AppResourceProvider {
    static let shared = AppResourceProvider()

    private var cachedURLs: [String: URL?] = [:]
    private var cachedData: [String: Data] = [:]

    private init() {}

    func url(for relativePath: String) -> URL? {
        if let cachedURL = cachedURLs[relativePath] {
            return cachedURL
        }

        let resolvedURL = updatedURL(for: relativePath) ?? bundledURL(for: relativePath)
        cachedURLs[relativePath] = resolvedURL
        return resolvedURL
    }

    func resourceExists(at relativePath: String) -> Bool {
        url(for: relativePath) != nil
    }

    func data(for relativePath: String) -> Data? {
        if let cachedData = cachedData[relativePath] {
            return cachedData
        }

        guard let url = url(for: relativePath) else {
            AppLogger.resources.warning("Resource not found: \(relativePath, privacy: .public)")
            return nil
        }

        do {
            let loadedData = try Data(contentsOf: url)
            cachedData[relativePath] = loadedData
            return loadedData
        } catch {
            AppLogger.resources.error("Failed to read resource \(relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func decode<T: Decodable>(_ type: T.Type, from relativePath: String) -> T? {
        guard let data = data(for: relativePath) else { return nil }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            AppLogger.resources.error("Failed to decode \(String(describing: type), privacy: .public) from \(relativePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func reloadCachedResources() {
        cachedURLs.removeAll()
        cachedData.removeAll()
    }

    private func updatedURL(for relativePath: String) -> URL? {
        let url = AppResourceStorage.updatedResourcesDirectory.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func bundledURL(for relativePath: String) -> URL? {
        let nsPath = relativePath as NSString
        let fileName = nsPath.lastPathComponent as NSString
        let resourceName = fileName.deletingPathExtension
        let fileExtension = fileName.pathExtension
        let directory = nsPath.deletingLastPathComponent
        let subdirectory = directory.isEmpty ? "StaticResources" : "StaticResources/\(directory)"

        return Bundle.main.url(
            forResource: resourceName,
            withExtension: fileExtension.isEmpty ? nil : fileExtension,
            subdirectory: subdirectory
        ) ?? Bundle.main.url(
            forResource: resourceName,
            withExtension: fileExtension.isEmpty ? nil : fileExtension
        )
    }
}
