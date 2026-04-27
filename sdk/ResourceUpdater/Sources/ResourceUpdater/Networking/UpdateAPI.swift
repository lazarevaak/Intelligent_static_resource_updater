//
//  UpdateAPI.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 26.01.2026.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class UpdateAPI: @unchecked Sendable {
    private let config: ResourceUpdaterConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(
        config: ResourceUpdaterConfig,
        session: URLSession = .shared
    ) {
        self.config = config
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func fetchLatestManifest(
        completion: @escaping @Sendable (Result<Manifest, Error>) -> Void
    ) {
        Task {
            do {
                completion(.success(try await fetchLatestManifest()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchLatestManifest() async throws -> Manifest {
        let request = makeRequest(path: "/v1/manifest/\(config.appId)/latest")
        let signed: SignedPayload<Manifest> = try await fetchSignedJSON(
            request: request,
            hashHeader: "X-Manifest-SHA256",
            signatureHeader: "X-Signature",
            signatureAlgorithmHeader: "X-Signature-Alg",
            signatureKeyIDHeader: "X-Signature-Key-Id"
        )
        return signed.payload
    }

    func fetchUpdates(fromVersion: String?) async throws -> UpdatesResponse {
        var components = URLComponents(
            url: config.baseURL.appendingPathComponent("v1/updates/\(config.appId)"),
            resolvingAgainstBaseURL: false
        )

        var items = [URLQueryItem(name: "sdkVersion", value: config.sdkVersion)]
        if let fromVersion {
            items.append(URLQueryItem(name: "fromVersion", value: fromVersion))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw ResourceUpdaterError.invalidResponse
        }

        let signed: SignedPayload<UpdatesResponse> = try await fetchSignedJSON(
            request: URLRequest(url: url),
            hashHeader: "X-Updates-SHA256",
            signatureHeader: "X-Updates-Signature",
            signatureAlgorithmHeader: "X-Updates-Signature-Alg",
            signatureKeyIDHeader: "X-Updates-Signature-Key-Id"
        )
        return signed.payload
    }

    func fetchManifest(descriptor: SignedObjectDescriptor) async throws -> Manifest {
        let signed: SignedPayload<Manifest> = try await fetchSignedJSON(
            request: URLRequest(url: absoluteURL(for: descriptor.url)),
            expectedHash: descriptor.sha256,
            expectedSignature: descriptor.signature,
            expectedSignatureAlgorithm: descriptor.signatureAlgorithm,
            expectedSignatureKeyID: descriptor.signatureKeyId,
            hashHeader: "X-Manifest-SHA256",
            signatureHeader: "X-Signature",
            signatureAlgorithmHeader: "X-Signature-Alg",
            signatureKeyIDHeader: "X-Signature-Key-Id"
        )
        return signed.payload
    }

    func fetchPatch(descriptor: SignedObjectDescriptor) async throws -> PatchArtifact {
        let signed: SignedPayload<PatchArtifact> = try await fetchSignedJSON(
            request: URLRequest(url: absoluteURL(for: descriptor.url)),
            expectedHash: descriptor.sha256,
            expectedSignature: descriptor.signature,
            expectedSignatureAlgorithm: descriptor.signatureAlgorithm,
            expectedSignatureKeyID: descriptor.signatureKeyId,
            hashHeader: "X-Patch-SHA256",
            signatureHeader: "X-Signature",
            signatureAlgorithmHeader: "X-Signature-Alg",
            signatureKeyIDHeader: "X-Signature-Key-Id"
        )
        return signed.payload
    }

    func fetchResource(hash: String) async throws -> Data {
        let request = makeRequest(path: "/v1/resource/\(config.appId)/hash/\(hash)")
        let (data, response) = try await session.data(for: request)
        let httpResponse = try requireHTTPResponse(response)
        try requireSuccessStatusCode(httpResponse.statusCode)

        let actualHash = CryptoSupport.sha256Hex(data)
        if actualHash != hash {
            throw ResourceUpdaterError.hashMismatch(expected: hash, actual: actualHash)
        }

        if let sizeHeader = httpResponse.value(forHTTPHeaderField: "X-Resource-Size"),
           let expectedSize = Int(sizeHeader),
           expectedSize != data.count {
            throw ResourceUpdaterError.sizeMismatch(expected: expectedSize, actual: data.count)
        }

        return data
    }

    private func fetchSigningKey(keyID: String) async throws -> SigningPublicKey {
        let request = makeRequest(path: "/v1/keys/\(keyID)")
        let (data, response) = try await session.data(for: request)
        let httpResponse = try requireHTTPResponse(response)
        try requireSuccessStatusCode(httpResponse.statusCode)
        return try decoder.decode(SigningPublicKey.self, from: data)
    }

    private func fetchSignedJSON<T: Decodable>(
        request: URLRequest,
        expectedHash: String? = nil,
        expectedSignature: String? = nil,
        expectedSignatureAlgorithm: String? = nil,
        expectedSignatureKeyID: String? = nil,
        hashHeader: String,
        signatureHeader: String,
        signatureAlgorithmHeader: String,
        signatureKeyIDHeader: String
    ) async throws -> SignedPayload<T> {
        let (data, response) = try await session.data(for: request)
        let httpResponse = try requireHTTPResponse(response)
        try requireSuccessStatusCode(httpResponse.statusCode)

        let hashFromHeader = try requireHeader(hashHeader, in: httpResponse)
        let signature = try requireHeader(signatureHeader, in: httpResponse)
        let signatureAlgorithm = try requireHeader(signatureAlgorithmHeader, in: httpResponse)
        let signatureKeyID = try requireHeader(signatureKeyIDHeader, in: httpResponse)

        if let expectedHash, expectedHash != hashFromHeader {
            throw ResourceUpdaterError.hashMismatch(expected: expectedHash, actual: hashFromHeader)
        }
        if let expectedSignature, expectedSignature != signature {
            throw ResourceUpdaterError.invalidHeader(signatureHeader)
        }
        if let expectedSignatureAlgorithm, expectedSignatureAlgorithm != signatureAlgorithm {
            throw ResourceUpdaterError.invalidSignatureAlgorithm(signatureAlgorithm)
        }
        if let expectedSignatureKeyID, expectedSignatureKeyID != signatureKeyID {
            throw ResourceUpdaterError.invalidHeader(signatureKeyIDHeader)
        }

        let actualHash = CryptoSupport.sha256Hex(data)
        if actualHash != hashFromHeader {
            throw ResourceUpdaterError.hashMismatch(expected: hashFromHeader, actual: actualHash)
        }
        if signatureAlgorithm.lowercased() != "ed25519" {
            throw ResourceUpdaterError.invalidSignatureAlgorithm(signatureAlgorithm)
        }

        let key = try await fetchSigningKey(keyID: signatureKeyID)
        try CryptoSupport.verifySignature(
            data: data,
            signatureBase64: signature,
            publicKeyBase64: key.publicKeyBase64
        )

        let payload = try decoder.decode(T.self, from: data)
        return SignedPayload(payload: payload, rawData: data)
    }

    private func makeRequest(path: String) -> URLRequest {
        URLRequest(url: absoluteURL(for: path))
    }

    private func absoluteURL(for path: String) -> URL {
        if let url = URL(string: path), url.scheme != nil {
            return url
        }

        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard let url = URL(string: trimmedPath, relativeTo: config.baseURL) else {
            return config.baseURL.appendingPathComponent(trimmedPath)
        }
        return url
    }

    private func requireHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResourceUpdaterError.invalidResponse
        }
        return httpResponse
    }

    private func requireSuccessStatusCode(_ statusCode: Int) throws {
        guard (200...299).contains(statusCode) else {
            throw ResourceUpdaterError.unexpectedStatusCode(statusCode)
        }
    }

    private func requireHeader(_ name: String, in response: HTTPURLResponse) throws -> String {
        guard let value = response.value(forHTTPHeaderField: name), !value.isEmpty else {
            throw ResourceUpdaterError.missingHeader(name)
        }
        return value
    }
}

private struct SignedPayload<T> {
    let payload: T
    let rawData: Data
}
