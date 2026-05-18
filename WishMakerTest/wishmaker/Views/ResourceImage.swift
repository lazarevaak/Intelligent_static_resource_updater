//
//  ResourceImage.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.
//

import UIKit

extension UIImage {
    static func resourceImage(at relativePath: String) -> UIImage? {
        guard let url = AppResourceProvider.shared.url(for: relativePath) else {
            AppLogger.resources.warning("Image resource not found: \(relativePath, privacy: .public)")
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }
}
