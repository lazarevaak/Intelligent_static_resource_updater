import CryptoKit
import Vapor

struct ManifestController {
    private struct ResourceUploadResponse: Content {
        let hash: String
        let size: Int
    }

    private struct PatchUploadResponse: Content {
        let hash: String
        let size: Int
    }

    private struct UpdatesQuery: Content {
        let fromVersion: String?
        let sdkVersion: String?
    }

    private let storage: ManifestStorage
    private let publishToken: String
    private let signatureService: SignatureService

    init(
        publicDirectory: String,
        artifactStorage: any ArtifactStorage,
        publishToken: String,
        signatureService: SignatureService
    ) {
        self.storage = ManifestStorage(
            publicDirectory: publicDirectory,
            artifactStorage: artifactStorage
        )
        self.publishToken = publishToken
        self.signatureService = signatureService
    }

    func getLatestManifest(req: Request) async throws -> Response {
        let appId = try requireParam(req, "appId")
        try validateIdentifier(appId, name: "appId")
        let manifest = try await storage.loadLatest(appId: appId)
        return try makeSignedManifestResponse(manifest)
    }

    func getManifest(req: Request) async throws -> Response {
        let appId = try requireParam(req, "appId")
        let version = try requireParam(req, "version")
        try validateIdentifier(appId, name: "appId")
        try validateIdentifier(version, name: "version")
        let manifest = try await storage.load(appId: appId, version: version)
        return try makeSignedManifestResponse(manifest)
    }

    func getUpdates(req: Request) async throws -> Response {
        let appId = try requireParam(req, "appId")
        try validateIdentifier(appId, name: "appId")

        let query = try req.query.decode(UpdatesQuery.self)
        if let fromVersion = query.fromVersion {
            try validateIdentifier(fromVersion, name: "fromVersion")
        }
        if let sdkVersion = query.sdkVersion {
            try validateVersionString(sdkVersion, name: "sdkVersion")
        }

        let latest = try await storage.loadLatest(appId: appId)
        let signedManifest = try signatureService.sign(latest)
        let manifestDescriptor = SignedObjectDescriptor(
            url: "/v1/manifest/\(appId)/version/\(latest.version)",
            sha256: signedManifest.sha256,
            signature: signedManifest.signatureBase64,
            signatureAlgorithm: signedManifest.algorithm,
            signatureKeyId: signedManifest.keyId,
            size: signedManifest.data.count
        )

        if query.fromVersion == latest.version {
            return try makeSignedUpdatesResponse(
                UpdatesResponse(
                decision: "no-update",
                appId: appId,
                fromVersion: query.fromVersion,
                latestVersion: latest.version,
                sdkVersion: query.sdkVersion,
                reason: "already-up-to-date",
                manifest: manifestDescriptor,
                patch: nil
                )
            )
        }

        guard let fromVersion = query.fromVersion else {
            return try makeSignedUpdatesResponse(
                UpdatesResponse(
                decision: "manifest-only",
                appId: appId,
                fromVersion: nil,
                latestVersion: latest.version,
                sdkVersion: query.sdkVersion,
                reason: "from-version-missing",
                manifest: manifestDescriptor,
                patch: nil
                )
            )
        }

        guard let sdkVersion = query.sdkVersion else {
            return try makeSignedUpdatesResponse(
                UpdatesResponse(
                decision: "manifest-only",
                appId: appId,
                fromVersion: fromVersion,
                latestVersion: latest.version,
                sdkVersion: nil,
                reason: "sdk-version-missing",
                manifest: manifestDescriptor,
                patch: nil
                )
            )
        }

        if compareVersions(sdkVersion, latest.minSdkVersion) == .orderedAscending {
            return try makeSignedUpdatesResponse(
                UpdatesResponse(
                decision: "manifest-only",
                appId: appId,
                fromVersion: fromVersion,
                latestVersion: latest.version,
                sdkVersion: sdkVersion,
                reason: "sdk-too-old",
                manifest: manifestDescriptor,
                patch: nil
                )
            )
        }

        do {
            let patch = try await storage.loadPatchArtifact(
                appId: appId,
                fromVersion: fromVersion,
                toVersion: latest.version
            )
            let patchSignature = try signatureService.sign(patch.data)
            let patchDescriptor = SignedObjectDescriptor(
                url: "/v1/patch/\(appId)/from/\(fromVersion)/to/\(latest.version)",
                sha256: patch.sha256,
                signature: patchSignature.signatureBase64,
                signatureAlgorithm: patchSignature.algorithm,
                signatureKeyId: patchSignature.keyId,
                size: patch.data.count
            )
            return try makeSignedUpdatesResponse(
                UpdatesResponse(
                decision: "patch",
                appId: appId,
                fromVersion: fromVersion,
                latestVersion: latest.version,
                sdkVersion: sdkVersion,
                reason: "patch-available",
                manifest: manifestDescriptor,
                patch: patchDescriptor
                )
            )
        } catch {
            return try makeSignedUpdatesResponse(
                UpdatesResponse(
                decision: "manifest-only",
                appId: appId,
                fromVersion: fromVersion,
                latestVersion: latest.version,
                sdkVersion: sdkVersion,
                reason: "patch-unavailable",
                manifest: manifestDescriptor,
                patch: nil
                )
            )
        }
    }

    func getSigningKeys(req: Request) throws -> [SigningPublicKey] {
        _ = req
        return signatureService.publicKeys()
    }

    func getSigningKey(req: Request) throws -> SigningPublicKey {
        let keyId = try requireParam(req, "keyId")
        try validateIdentifier(keyId, name: "keyId")
        guard let key = signatureService.publicKey(keyId: keyId) else {
            throw Abort(.notFound, reason: "signing key not found")
        }
        return key
    }

    func updateManifest(req: Request) async throws -> HTTPStatus {
        try authorizePublish(req: req)

        let appId = try requireParam(req, "appId")
        let version = try requireParam(req, "version")
        let requestId = try requireRequestId(req)
        try validateIdentifier(appId, name: "appId")
        try validateIdentifier(version, name: "version")

        let manifest = try req.content.decode(Manifest.self)
        try validate(manifest)
        if manifest.version != version {
            throw Abort(.badRequest, reason: "manifest.version must match URL version")
        }

        let result = try await storage.save(
            manifest,
            appId: appId,
            version: version,
            overwrite: false,
            requestId: requestId,
            payloadHash: try payloadHash(for: manifest)
        )

        switch result {
        case .created:
            return .created
        case .replayed:
            return .ok
        }
    }

    func getPatchMeta(req: Request) async throws -> PatchMeta {
        let appId = try requireParam(req, "appId")
        let fromVersion = try requireParam(req, "fromVersion")
        let toVersion = try requireParam(req, "toVersion")
        try validateIdentifier(appId, name: "appId")
        try validateIdentifier(fromVersion, name: "fromVersion")
        try validateIdentifier(toVersion, name: "toVersion")

        return try await storage.buildPatchMeta(
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion
        )
    }

    func getPatch(req: Request) async throws -> Response {
        let appId = try requireParam(req, "appId")
        let fromVersion = try requireParam(req, "fromVersion")
        let toVersion = try requireParam(req, "toVersion")
        try validateIdentifier(appId, name: "appId")
        try validateIdentifier(fromVersion, name: "fromVersion")
        try validateIdentifier(toVersion, name: "toVersion")

        let artifact = try await storage.loadPatchArtifact(
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion
        )

        let signature = try signatureService.sign(artifact.data)
        let response = Response(status: .ok, body: .init(data: artifact.data))
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.headers.replaceOrAdd(
            name: .contentDisposition,
            value: "attachment; filename=\"\(fromVersion)-\(toVersion).patch.json\""
        )
        response.headers.replaceOrAdd(name: "X-Patch-SHA256", value: artifact.sha256)
        response.headers.replaceOrAdd(name: "X-Signature", value: signature.signatureBase64)
        response.headers.replaceOrAdd(name: "X-Signature-Alg", value: signature.algorithm)
        response.headers.replaceOrAdd(name: "X-Signature-Key-Id", value: signature.keyId)
        return response
    }

    func uploadResource(req: Request) async throws -> Response {
        try authorizePublish(req: req)
        let appId = try requireParam(req, "appId")
        try validateIdentifier(appId, name: "appId")

        let resourcePath = try requireHeader(req, "X-Resource-Path")
        try validateResourcePath(resourcePath)

        let hash = try requireHeader(req, "X-Resource-Hash")
        try validateHash(hash)

        let sizeHeader = req.headers.first(name: "X-Resource-Size")
        let expectedSize = try parseOptionalNonNegativeInt(sizeHeader, name: "X-Resource-Size")

        guard let bodyBuffer = req.body.data else {
            throw Abort(.badRequest, reason: "resource body is empty")
        }
        let data = Data(buffer: bodyBuffer)
        if data.isEmpty {
            throw Abort(.badRequest, reason: "resource body is empty")
        }

        let result = try await storage.uploadResource(
            appId: appId,
            path: resourcePath,
            expectedHash: hash,
            expectedSize: expectedSize,
            data: data
        )

        let status: HTTPStatus = result.created ? .created : .ok
        let response = Response(status: status)
        try response.content.encode(ResourceUploadResponse(hash: result.hash, size: result.size))
        return response
    }

    func uploadPatch(req: Request) async throws -> Response {
        try authorizePublish(req: req)

        let appId = try requireParam(req, "appId")
        let fromVersion = try requireParam(req, "fromVersion")
        let toVersion = try requireParam(req, "toVersion")
        let requestId = try requireRequestId(req)
        try validateIdentifier(appId, name: "appId")
        try validateIdentifier(fromVersion, name: "fromVersion")
        try validateIdentifier(toVersion, name: "toVersion")

        let hash = try requireHeader(req, "X-Patch-SHA256")
        try validateHash(hash)

        let expectedSize = try parseOptionalNonNegativeInt(
            req.headers.first(name: "X-Patch-Size"),
            name: "X-Patch-Size"
        )

        guard let bodyBuffer = req.body.data else {
            throw Abort(.badRequest, reason: "patch body is empty")
        }
        let data = Data(buffer: bodyBuffer)
        if data.isEmpty {
            throw Abort(.badRequest, reason: "patch body is empty")
        }

        let result = try await storage.uploadPatchArtifact(
            appId: appId,
            fromVersion: fromVersion,
            toVersion: toVersion,
            requestId: requestId,
            payloadHash: hash.lowercased(),
            expectedHash: hash.lowercased(),
            expectedSize: expectedSize,
            data: data
        )

        let status: HTTPStatus
        switch result {
        case .created:
            status = .created
        case .replayed:
            status = .ok
        }
        let response = Response(status: status)
        try response.content.encode(PatchUploadResponse(hash: hash.lowercased(), size: data.count))
        return response
    }

    func getResource(req: Request) async throws -> Response {
        let appId = try requireParam(req, "appId")
        let hash = try requireParam(req, "hash")
        try validateIdentifier(appId, name: "appId")
        try validateHash(hash)

        let data = try await storage.loadResource(appId: appId, hash: hash)
        let response = Response(status: .ok, body: .init(data: data))
        response.headers.replaceOrAdd(name: .contentType, value: "application/octet-stream")
        response.headers.replaceOrAdd(name: "X-Resource-Hash", value: hash)
        response.headers.replaceOrAdd(name: "X-Resource-Size", value: String(data.count))
        return response
    }

    private func validate(_ manifest: Manifest) throws {
        if manifest.schemaVersion < 1 {
            throw Abort(.badRequest, reason: "manifest.schemaVersion must be >= 1")
        }
        try validateVersionString(manifest.minSdkVersion, name: "manifest.minSdkVersion")
        try validateVersionString(manifest.version, name: "manifest.version")

        var seenPaths = Set<String>()
        for entry in manifest.resources {
            let path = entry.path.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.isEmpty {
                throw Abort(.badRequest, reason: "resource.path is required")
            }
            try validateResourcePath(path)
            if !seenPaths.insert(path).inserted {
                throw Abort(.badRequest, reason: "duplicate resource path: \(path)")
            }
            if entry.hash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw Abort(.badRequest, reason: "resource.hash is required")
            }
            try validateHash(entry.hash)
            if entry.size < 0 {
                throw Abort(.badRequest, reason: "resource.size must be >= 0")
            }
        }
    }

    private func validateIdentifier(_ value: String, name: String) throws {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw Abort(.badRequest, reason: "\(name) is required")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        if value.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw Abort(.badRequest, reason: "\(name) contains invalid characters")
        }
    }

    private func validateVersionString(_ value: String, name: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw Abort(.badRequest, reason: "\(name) is required")
        }
        let allowed = CharacterSet(charactersIn: "0123456789.")
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw Abort(.badRequest, reason: "\(name) has invalid format")
        }
    }

    private func validateResourcePath(_ path: String) throws {
        if path.hasPrefix("/") || path.hasPrefix("\\") {
            throw Abort(.badRequest, reason: "resource.path must be relative")
        }
        if path.contains("..") {
            throw Abort(.badRequest, reason: "resource.path must not contain '..'")
        }
    }

    private func validateHash(_ hash: String) throws {
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count != 64 {
            throw Abort(.badRequest, reason: "resource.hash must be 64-char sha256 hex")
        }
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            throw Abort(.badRequest, reason: "resource.hash must be sha256 hex")
        }
    }

    private func authorizePublish(req: Request) throws {
        let bearer = req.headers.bearerAuthorization?.token
        let headerToken = req.headers.first(name: "X-CI-Token")
        let token = bearer ?? headerToken
        guard token == publishToken else {
            throw Abort(.unauthorized, reason: "invalid CI token")
        }
    }

    private func requireRequestId(_ req: Request) throws -> String {
        let value = req.headers.first(name: "X-Request-Id") ?? req.headers.first(name: "Idempotency-Key")
        guard let value else {
            throw Abort(.badRequest, reason: "X-Request-Id header is required")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw Abort(.badRequest, reason: "X-Request-Id header is empty")
        }
        return trimmed
    }

    private func payloadHash(for manifest: Manifest) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeSignedManifestResponse(_ manifest: Manifest) throws -> Response {
        let signature = try signatureService.sign(manifest)
        let response = Response(status: .ok, body: .init(data: signature.data))
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.headers.replaceOrAdd(name: "X-Manifest-SHA256", value: signature.sha256)
        response.headers.replaceOrAdd(name: "X-Signature", value: signature.signatureBase64)
        response.headers.replaceOrAdd(name: "X-Signature-Alg", value: signature.algorithm)
        response.headers.replaceOrAdd(name: "X-Signature-Key-Id", value: signature.keyId)
        return response
    }

    private func makeSignedUpdatesResponse(_ payload: UpdatesResponse) throws -> Response {
        let signature = try signatureService.sign(payload)
        let response = Response(status: .ok, body: .init(data: signature.data))
        response.headers.replaceOrAdd(name: .contentType, value: "application/json")
        response.headers.replaceOrAdd(name: "X-Updates-SHA256", value: signature.sha256)
        response.headers.replaceOrAdd(name: "X-Updates-Signature", value: signature.signatureBase64)
        response.headers.replaceOrAdd(name: "X-Updates-Signature-Alg", value: signature.algorithm)
        response.headers.replaceOrAdd(name: "X-Updates-Signature-Key-Id", value: signature.keyId)
        return response
    }

    private func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let maxCount = max(lhsParts.count, rhsParts.count)
        for index in 0..<maxCount {
            let l = index < lhsParts.count ? lhsParts[index] : 0
            let r = index < rhsParts.count ? rhsParts[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private func requireParam(_ req: Request, _ name: String) throws -> String {
        guard let value = req.parameters.get(name) else {
            throw Abort(.badRequest, reason: "missing parameter: \(name)")
        }
        return value
    }

    private func requireHeader(_ req: Request, _ name: String) throws -> String {
        guard let value = req.headers.first(name: name) else {
            throw Abort(.badRequest, reason: "\(name) header is required")
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw Abort(.badRequest, reason: "\(name) header is empty")
        }
        return trimmed
    }

    private func parseOptionalNonNegativeInt(_ value: String?, name: String) throws -> Int? {
        guard let value else { return nil }
        guard let parsed = Int(value), parsed >= 0 else {
            throw Abort(.badRequest, reason: "\(name) must be a non-negative integer")
        }
        return parsed
    }
}
