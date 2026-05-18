//
//  ResourceImage.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.
//

import UIKit

private struct CachedResourceImage {
    let data: Data
    let image: UIImage
}

@MainActor
private enum ResourceImageCache {
    static var images: [String: CachedResourceImage] = [:]
}

@MainActor
extension UIImage {
    static func resourceImage(at relativePath: String) -> UIImage? {
        guard let data = AppResourceProvider.shared.data(for: relativePath) else {
            return nil
        }

        if let cached = ResourceImageCache.images[relativePath],
           cached.data == data {
            return cached.image
        }

        guard let image = UIImage(data: data) else {
            AppLogger.resources.warning("Failed to decode image resource: \(relativePath, privacy: .public)")
            return nil
        }

        ResourceImageCache.images[relativePath] = CachedResourceImage(
            data: data,
            image: image
        )
        return image
    }
}
