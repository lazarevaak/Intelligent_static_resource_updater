//
//  Localization.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation

enum Localization {
    private static let cacheLock = NSLock()
    private static var cachedTables: [String: [String: String]] = [:]

    static func resetCache() {
        cacheLock.lock()
        cachedTables.removeAll()
        cacheLock.unlock()
    }

    static func string(_ key: String, language: AppLanguage) -> String {
        for languageCode in languageCodes(for: language) {
            if let value = table(for: languageCode)[key] {
                return value
            }
        }

        return key
    }

    private static func languageCodes(for language: AppLanguage) -> [String] {
        switch language {
        case .english:
            return ["en"]
        case .russian:
            return ["ru", "en"]
        case .system:
            let preferred = Locale.preferredLanguages.compactMap { identifier -> String? in
                let normalized = identifier.replacingOccurrences(of: "_", with: "-")
                let base = normalized.split(separator: "-").first.map(String.init)
                return existingLocalizationCode(for: normalized) ?? base.flatMap(existingLocalizationCode)
            }
            return Array(NSOrderedSet(array: preferred + ["en"])) as? [String] ?? ["en"]
        }
    }

    private static func existingLocalizationCode(for languageCode: String) -> String? {
        let path = AppResourcePath.localization(languageCode)
        return AppResourceProvider.shared.resourceExists(at: path) ? languageCode : nil
    }

    private static func table(for languageCode: String) -> [String: String] {
        cacheLock.lock()
        if let cachedTable = cachedTables[languageCode] {
            cacheLock.unlock()
            return cachedTable
        }
        cacheLock.unlock()

        let table = AppResourceProvider.shared.decode(
            [String: String].self,
            from: AppResourcePath.localization(languageCode)
        ) ?? [:]

        cacheLock.lock()
        cachedTables[languageCode] = table
        cacheLock.unlock()

        return table
    }
}
