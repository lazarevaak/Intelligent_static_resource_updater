import Foundation
import XCTest
@testable import ResourceUpdater

final class PatchStoreTests: XCTestCase {
    func testApplyPatchUpdatesResourcesAndVersion() throws {
        let context = try makeStoreContext()
        let store = LocalResourceStore(rootDirectory: context.rootDirectory)

        let oldData = Data("old".utf8)
        let addedData = Data("new-file".utf8)
        let replacedData = Data("hello-new".utf8)

        try writeResource(oldData, at: TestConstants.messagePath, in: context.resourcesDirectory)
        try writeResource(Data("delete-me".utf8), at: TestConstants.removePath, in: context.resourcesDirectory)
        try store.save(manifest: makeManifest(
            version: TestConstants.version100,
            resources: [
                makeResourceEntry(path: TestConstants.messagePath, data: oldData),
                makeResourceEntry(path: TestConstants.removePath, data: Data("delete-me".utf8))
            ]
        ))

        let patch = PatchArtifact(
            schemaVersion: 1,
            appId: TestConstants.appID,
            fromVersion: TestConstants.version100,
            toVersion: TestConstants.version110,
            generatedAt: Date(),
            operations: [
                PatchOperation(
                    op: "add",
                    path: TestConstants.newPath,
                    hash: sha256(addedData),
                    size: addedData.count,
                    dataBase64: addedData.base64EncodedString(),
                    delta: nil
                ),
                PatchOperation(
                    op: "replace",
                    path: TestConstants.messagePath,
                    hash: sha256(replacedData),
                    size: replacedData.count,
                    dataBase64: replacedData.base64EncodedString(),
                    delta: nil
                )
            ]
        )

        let targetManifest = makeManifest(
            version: TestConstants.version110,
            resources: [
                makeResourceEntry(path: TestConstants.messagePath, data: replacedData),
                makeResourceEntry(path: TestConstants.newPath, data: addedData),
                makeResourceEntry(path: TestConstants.removePath, data: Data("delete-me".utf8))
            ]
        )

        try store.applyPatch(patch, targetManifest: targetManifest)

        XCTAssertEqual(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent(TestConstants.messagePath)), replacedData)
        XCTAssertEqual(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent(TestConstants.newPath)), addedData)
        XCTAssertEqual(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent(TestConstants.removePath)), Data("delete-me".utf8))
        XCTAssertEqual(store.currentVersion(), TestConstants.version110)
    }

    func testApplyPatchRollsBackWhenBaseResourceIsMissing() throws {
        let context = try makeStoreContext()
        let store = LocalResourceStore(rootDirectory: context.rootDirectory)

        let oldData = Data("old".utf8)
        try writeResource(oldData, at: "texts/message.txt", in: context.resourcesDirectory)
        try store.save(manifest: makeManifest(
            version: "1.0.0",
            resources: [makeResourceEntry(path: "texts/message.txt", data: oldData)]
        ))

        let replacement = Data("replacement".utf8)
        let patch = PatchArtifact(
            schemaVersion: 1,
            appId: "demoapp",
            fromVersion: "1.0.0",
            toVersion: "1.1.0",
            generatedAt: Date(),
            operations: [
                PatchOperation(
                    op: "replace",
                    path: "texts/missing.txt",
                    hash: sha256(replacement),
                    size: replacement.count,
                    dataBase64: nil,
                    delta: BinaryDeltaPatch(
                        algorithm: "splice-v1",
                        baseHash: sha256(oldData),
                        baseSize: oldData.count,
                        targetHash: sha256(replacement),
                        targetSize: replacement.count,
                        operations: [
                            BinaryDeltaOperation(offset: 0, deleteLength: oldData.count, dataBase64: replacement.base64EncodedString())
                        ]
                    )
                )
            ]
        )

        let targetManifest = makeManifest(
            version: "1.1.0",
            resources: [makeResourceEntry(path: "texts/missing.txt", data: replacement)]
        )

        XCTAssertThrowsError(try store.applyPatch(patch, targetManifest: targetManifest)) { error in
            guard case ResourceUpdaterError.resourceNotFound(let path) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, "texts/missing.txt")
        }

        XCTAssertEqual(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent("texts/message.txt")), oldData)
        XCTAssertEqual(store.currentVersion(), "1.0.0")
    }

    func testApplyPatchRollsBackWhenPatchIsInvalid() throws {
        let context = try makeStoreContext()
        let store = LocalResourceStore(rootDirectory: context.rootDirectory)

        let originalData = Data("abcdef".utf8)
        try writeResource(originalData, at: "texts/message.txt", in: context.resourcesDirectory)
        try store.save(manifest: makeManifest(
            version: "1.0.0",
            resources: [makeResourceEntry(path: "texts/message.txt", data: originalData)]
        ))

        let invalidPatch = PatchArtifact(
            schemaVersion: 1,
            appId: "demoapp",
            fromVersion: "1.0.0",
            toVersion: "1.1.0",
            generatedAt: Date(),
            operations: [
                PatchOperation(
                    op: "replace",
                    path: "texts/message.txt",
                    hash: sha256(originalData),
                    size: originalData.count,
                    dataBase64: nil,
                    delta: BinaryDeltaPatch(
                        algorithm: "splice-v1",
                        baseHash: sha256(originalData),
                        baseSize: originalData.count,
                        targetHash: sha256(originalData),
                        targetSize: originalData.count,
                        operations: [
                            BinaryDeltaOperation(offset: 99, deleteLength: 1, dataBase64: Data("x".utf8).base64EncodedString())
                        ]
                    )
                )
            ]
        )

        let targetManifest = makeManifest(
            version: "1.1.0",
            resources: [makeResourceEntry(path: "texts/message.txt", data: originalData)]
        )

        XCTAssertThrowsError(try store.applyPatch(invalidPatch, targetManifest: targetManifest)) { error in
            guard case ResourceUpdaterError.invalidPatchOperation(let reason) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(reason, "splice out of range")
        }

        XCTAssertEqual(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent("texts/message.txt")), originalData)
        XCTAssertEqual(store.currentVersion(), "1.0.0")
    }

    func testApplyPatchRemoveDeletesResource() throws {
        let context = try makeStoreContext()
        let store = LocalResourceStore(rootDirectory: context.rootDirectory)

        let keptData = Data("keep".utf8)
        let removedData = Data("remove".utf8)
        try writeResource(keptData, at: "texts/keep.txt", in: context.resourcesDirectory)
        try writeResource(removedData, at: "texts/remove.txt", in: context.resourcesDirectory)
        try store.save(manifest: makeManifest(
            version: "1.0.0",
            resources: [
                makeResourceEntry(path: "texts/keep.txt", data: keptData),
                makeResourceEntry(path: "texts/remove.txt", data: removedData)
            ]
        ))

        let patch = PatchArtifact(
            schemaVersion: 1,
            appId: "demoapp",
            fromVersion: "1.0.0",
            toVersion: "1.1.0",
            generatedAt: Date(),
            operations: [
                PatchOperation(
                    op: "remove",
                    path: "texts/remove.txt",
                    hash: nil,
                    size: nil,
                    dataBase64: nil,
                    delta: nil
                )
            ]
        )

        let targetManifest = makeManifest(
            version: "1.1.0",
            resources: [makeResourceEntry(path: "texts/keep.txt", data: keptData)]
        )

        try store.applyPatch(patch, targetManifest: targetManifest)

        XCTAssertEqual(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent("texts/keep.txt")), keptData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.resourcesDirectory.appendingPathComponent("texts/remove.txt").path))
        XCTAssertEqual(store.currentVersion(), "1.1.0")
    }
}
