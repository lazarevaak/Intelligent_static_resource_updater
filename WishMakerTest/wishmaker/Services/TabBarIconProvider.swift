//
//  TabBarIconProvider.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation
import UIKit

@MainActor
final class TabBarIconProvider {
    struct IconSet {
        let list: UIImage?
        let bolt: UIImage?
        let location: UIImage?
        let profile: UIImage?
    }

    static let shared = TabBarIconProvider()

    private init() {}

    func makeIconSet() -> IconSet {
        IconSet(
            list: loadImage(named: "tab-list", fallbackSystemName: "menucard.fill"),
            bolt: loadImage(named: "tab-bolt", fallbackSystemName: "bolt.fill"),
            location: loadImage(named: "tab-location", fallbackSystemName: "paperplane.fill"),
            profile: loadImage(named: "tab-profile", fallbackSystemName: "person.fill")
        )
    }

    private func loadImage(named name: String, fallbackSystemName: String) -> UIImage? {
        if let image = loadUpdatedImage(named: name) {
            return image.withRenderingMode(.alwaysTemplate)
        }

        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        return UIImage(systemName: fallbackSystemName, withConfiguration: configuration)?
            .withRenderingMode(.alwaysTemplate)
    }

    private func loadUpdatedImage(named name: String) -> UIImage? {
        let extensions = ["png", "pdf", "jpg", "jpeg"]

        for fileExtension in extensions {
            if let fileURL = AppResourceProvider.shared.url(for: "tabbar/\(name).\(fileExtension)"),
               let image = UIImage(contentsOfFile: fileURL.path) {
                return image
            }
        }

        return nil
    }
}
