//
//  Manifest.swift
//  ResourceUpdateServer
//
//  Created by Karabelnikov Stepan on 01.02.2026.
//

import Vapor

struct Manifest: Content {
    let version: String
    let generatedAt: Date
    let resources: [ResourceEntry]
}
