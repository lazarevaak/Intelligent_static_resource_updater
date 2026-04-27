import CryptoKit
import Foundation
@testable import ResourceUpdater

enum TestConstants {
    static let appID = "demoapp"
    static let sdkVersion = "1.0"
    static let version100 = "1.0.0"
    static let version110 = "1.1.0"

    static let messagePath = "texts/message.txt"
    static let newPath = "texts/new.txt"
    static let removePath = "texts/remove.txt"
    static let keepPath = "texts/keep.txt"
    static let helloPath = "texts/hello.txt"
    static let missingPath = "texts/missing.txt"
}

struct StoreContext {
    let rootDirectory: URL
    let resourcesDirectory: URL
}

struct SigningFixture: @unchecked Sendable {
    let privateKey: Curve25519.Signing.PrivateKey
    let publicKey: SigningPublicKey

    init() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        self.privateKey = privateKey
        self.publicKey = SigningPublicKey(
            keyId: "main",
            alg: "ed25519",
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString(),
            createdAt: Date(timeIntervalSince1970: 0),
            active: true
        )
    }
}

func makeStoreContext() throws -> StoreContext {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let resources = root.appendingPathComponent("resources", isDirectory: true)
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true, attributes: nil)
    return StoreContext(rootDirectory: root, resourcesDirectory: resources)
}

func makeConfig(storageDirectory: URL) -> ResourceUpdaterConfig {
    ResourceUpdaterConfig(
        baseURL: URL(string: "https://example.test")!,
        appId: TestConstants.appID,
        sdkVersion: TestConstants.sdkVersion,
        storageDirectory: storageDirectory
    )
}

func writeResource(_ data: Data, at path: String, in resourcesDirectory: URL) throws {
    let fileURL = resourcesDirectory.appendingPathComponent(path)
    try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try data.write(to: fileURL, options: .atomic)
}

func makeManifest(version: String, resources: [ResourceEntry]) -> Manifest {
    Manifest(
        schemaVersion: 1,
        minSdkVersion: TestConstants.sdkVersion,
        version: version,
        generatedAt: Date(timeIntervalSince1970: 0),
        resources: resources
    )
}

func makeResourceEntry(path: String, data: Data) -> ResourceEntry {
    ResourceEntry(path: path, hash: sha256(data), size: data.count)
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
