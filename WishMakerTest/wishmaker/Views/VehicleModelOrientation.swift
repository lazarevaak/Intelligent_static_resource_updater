//
//  VehicleModelOrientation.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 28.04.2026.

import SceneKit

enum VehicleModelOrientation {
    static let frontYaw: Float = .pi
    static let rearYaw: Float = 0
    static let leftYaw: Float = .pi / 2
    static let rightYaw: Float = -.pi / 2
    static let initialPitch: Float = 0.18

    static let dashboardEulerAngles = SCNVector3(x: 0, y: frontYaw, z: 0)
}
