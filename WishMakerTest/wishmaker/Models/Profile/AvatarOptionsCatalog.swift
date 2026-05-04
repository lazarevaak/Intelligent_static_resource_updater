//
//  AvatarOptionsCatalog.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.

import Foundation

enum AvatarOptionsCatalog {
    static var options: [String] {
        AppResourceProvider.shared.decode(
            [String].self,
            from: AppResourcePath.avatarOptions
        ) ?? [
            "person.fill",
            "person.crop.circle",
            "person.crop.circle.fill",
            "person.crop.circle.badge.plus",
            "car.fill"
        ]
    }
}
