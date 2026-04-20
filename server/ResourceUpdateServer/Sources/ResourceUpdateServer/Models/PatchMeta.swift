import Vapor

struct PatchMeta: Content {
    let appId: String
    let fromVersion: String
    let toVersion: String
    let generatedAt: Date
    let added: [ResourceEntry]
    let changed: [ChangedResource]
    let removed: [String]
}

struct ChangedResource: Content {
    let path: String
    let fromHash: String
    let toHash: String
    let size: Int
}
