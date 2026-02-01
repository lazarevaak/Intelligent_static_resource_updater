//
//  ResourceEntry.swift
//  ResourceUpdateServer
//
//  Created by Karabelnikov Stepan on 01.02.2026.
//

import Vapor

struct ResourceEntry: Content {
    let path: String
    let hash: String
    let size: Int
}
