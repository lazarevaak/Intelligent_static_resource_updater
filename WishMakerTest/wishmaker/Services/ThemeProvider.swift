//
//  ThemeProvider.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import Foundation
import UIKit

@MainActor
final class ThemeProvider: ObservableObject {
    static let shared = ThemeProvider()

    @Published private(set) var theme: AppTheme = .default

    private init() {
        theme = loadThemeFromDisk() ?? .default
    }

    func reloadTheme() {
        theme = loadThemeFromDisk() ?? .default
    }

    func color(named name: String, fallbackHex: String) -> UIColor {
        let hex = theme.colors[name] ?? fallbackHex
        if let color = UIColor(hex: hex) {
            return color
        }

        AppLogger.resources.warning("Invalid theme color \(name, privacy: .public): \(hex, privacy: .public)")
        return UIColor(hex: fallbackHex) ?? .black
    }

    private func loadThemeFromDisk() -> AppTheme? {
        AppResourceProvider.shared.decode(AppTheme.self, from: AppResourcePath.theme)
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if string.hasPrefix("#") { string.removeFirst() }

        guard string.count == 6 || string.count == 8 else { return nil }
        guard string.allSatisfy(\.isHexDigit) else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: string).scanHexInt64(&value) else { return nil }

        let a, r, g, b: UInt64
        if string.count == 8 {
            a = (value & 0xFF00_0000) >> 24
            r = (value & 0x00FF_0000) >> 16
            g = (value & 0x0000_FF00) >> 8
            b = (value & 0x0000_00FF)
        } else {
            a = 255
            r = (value & 0xFF00_00) >> 16
            g = (value & 0x00FF_00) >> 8
            b = (value & 0x0000_FF)
        }

        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: CGFloat(a) / 255.0
        )
    }
}
