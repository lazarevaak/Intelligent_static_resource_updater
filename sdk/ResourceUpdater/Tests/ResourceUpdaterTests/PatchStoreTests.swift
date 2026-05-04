import Foundation
import Testing

@testable import ResourceUpdater

struct PatchStoreTests {
    @Test func applyPatchUpdatesResourcesAndVersion() throws {
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

        #expect(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent(TestConstants.messagePath)) == replacedData)
        #expect(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent(TestConstants.newPath)) == addedData)
        #expect(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent(TestConstants.removePath)) == Data("delete-me".utf8))
        #expect(store.currentVersion() == TestConstants.version110)
    }

    @Test func applyPatchRollsBackWhenBaseResourceIsMissing() throws {
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

        do {
            try store.applyPatch(patch, targetManifest: targetManifest)
            Issue.record("expected resourceNotFound")
        } catch ResourceUpdaterError.resourceNotFound(let path) {
            #expect(path == "texts/missing.txt")
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent("texts/message.txt")) == oldData)
        #expect(store.currentVersion() == "1.0.0")
    }

    @Test func applyPatchRollsBackWhenPatchIsInvalid() throws {
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

        do {
            try store.applyPatch(invalidPatch, targetManifest: targetManifest)
            Issue.record("expected invalidPatchOperation")
        } catch ResourceUpdaterError.invalidPatchOperation(let reason) {
            #expect(reason == "splice out of range")
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent("texts/message.txt")) == originalData)
        #expect(store.currentVersion() == "1.0.0")
    }

    @Test func applyPatchRemoveDeletesResource() throws {
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

        #expect(try Data(contentsOf: context.resourcesDirectory.appendingPathComponent("texts/keep.txt")) == keptData)
        #expect(!FileManager.default.fileExists(atPath: context.resourcesDirectory.appendingPathComponent("texts/remove.txt").path))
        #expect(store.currentVersion() == "1.1.0")
    }
}
