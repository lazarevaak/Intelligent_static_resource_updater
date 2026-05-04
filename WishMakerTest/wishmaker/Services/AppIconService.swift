//
//  AppIconService.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.

import UIKit

@MainActor
final class AppIconService {
    static let shared = AppIconService()

    private let allowedAlternateIconNames: Set<String?> = [nil, "AppIcon2"]

    private init() {}

    func applyConfiguredIcon() {
        guard UIApplication.shared.supportsAlternateIcons else {
            AppLogger.resources.warning("Alternate app icons are not supported on this device")
            return
        }

        let configuration = AppResourceProvider.shared.decode(
            AppConfiguration.self,
            from: AppResourcePath.appConfiguration
        )
        let requestedIconName = normalizedIconName(configuration?.alternateAppIconName)

        guard allowedAlternateIconNames.contains(requestedIconName) else {
            AppLogger.resources.warning("Ignored unsupported app icon name: \(requestedIconName ?? "primary", privacy: .public)")
            return
        }

        guard UIApplication.shared.alternateIconName != requestedIconName else {
            return
        }

        UIApplication.shared.setAlternateIconName(requestedIconName) { error in
            if let error {
                AppLogger.resources.error("Failed to apply app icon \(requestedIconName ?? "primary", privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func normalizedIconName(_ iconName: String?) -> String? {
        guard let iconName = iconName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !iconName.isEmpty,
              iconName.lowercased() != "primary" else {
            return nil
        }

        return iconName
    }
}
