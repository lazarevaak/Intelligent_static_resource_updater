import ArgumentParser
import CryptoKit
import Foundation

struct ResourceUpdateCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resource-cli",
        abstract: "Local tooling for resource manifest publishing workflows.",
        subcommands: [
            PublishLocalCommand.self,
            DryRunCommand.self,
            ValidateCommand.self,
            CleanupCommand.self,
        ]
    )
}

struct PublishLocalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "publish-local",
        abstract: "Upload resources and publish manifest using server API."
    )

    @Option(name: .customLong("base-url"), help: "Server base URL, e.g. http://127.0.0.1:8080/")
    var baseURL: String

    @Option(name: .customLong("app-id"), help: "Application identifier.")
    var appId: String

    @Option(name: .customLong("version"), help: "Manifest version to publish.")
    var version: String

    @Option(name: .customLong("resources-dir"), help: "Directory with static resources.")
    var resourcesDir: String

    @Option(name: .customLong("min-sdk-version"), help: "Minimum SDK version in manifest.")
    var minSdkVersion: String = "1.0"

    @Option(name: .customLong("request-id"), help: "Idempotency request id. Defaults to random UUID.")
    var requestId: String?

    @Option(name: .customLong("token"), help: "Publish token. If omitted, CI_PUBLISH_TOKEN env is used.")
    var token: String?

    mutating func run() async throws {
        let baseURL = try CLIShared.parseBaseURL(baseURL)
        let (resourcesDirURL, resources) = try CLIShared.scanDirectory(resourcesDir)
        let prepared = try CLIShared.prepareManifest(
            appId: appId,
            version: version,
            minSdkVersion: minSdkVersion,
            resourcesDirURL: resourcesDirURL,
            resources: resources
        )

        let publishToken = token ?? ProcessInfo.processInfo.environment["CI_PUBLISH_TOKEN"] ?? ""
        if publishToken.isEmpty {
            throw ValidationError("missing token: provide --token or set CI_PUBLISH_TOKEN")
        }

        let report = try await CLIShared.publish(
            baseURL: baseURL,
            token: publishToken,
            appId: appId,
            version: version,
            requestId: requestId ?? UUID().uuidString,
            resources: prepared.resources,
            manifest: prepared.manifest
        )

        print("publish-local completed")
        print("appId: \(appId)")
        print("version: \(version)")
        print("resources_dir: \(resourcesDirURL.path)")
        print("resources_total: \(prepared.resources.count)")
        print("resources_uploaded: \(report.uploadedCount)")
        print("resources_skipped: \(report.skippedCount)")
        print("manifest_status: \(report.manifestStatusCode)")
    }
}

struct DryRunCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dry-run",
        abstract: "Build manifest from local resources and print summary without uploading."
    )

    @Option(name: .customLong("app-id"), help: "Application identifier.")
    var appId: String

    @Option(name: .customLong("version"), help: "Manifest version to build.")
    var version: String

    @Option(name: .customLong("resources-dir"), help: "Directory with static resources.")
    var resourcesDir: String

    @Option(name: .customLong("min-sdk-version"), help: "Minimum SDK version in manifest.")
    var minSdkVersion: String = "1.0"

    @Flag(name: .customLong("json"), help: "Print full manifest JSON.")
    var json: Bool = false

    mutating func run() throws {
        let (resourcesDirURL, resources) = try CLIShared.scanDirectory(resourcesDir)
        let prepared = try CLIShared.prepareManifest(
            appId: appId,
            version: version,
            minSdkVersion: minSdkVersion,
            resourcesDirURL: resourcesDirURL,
            resources: resources
        )

        print("dry-run completed")
        print("appId: \(appId)")
        print("version: \(version)")
        print("resources_dir: \(resourcesDirURL.path)")
        print("resources_total: \(prepared.resources.count)")

        if let first = prepared.resources.first {
            print("first_resource: \(first.entry.path)")
        }
        if let last = prepared.resources.last {
            print("last_resource: \(last.entry.path)")
        }

        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(prepared.manifest)
            print(String(decoding: data, as: UTF8.self))
        }
    }
}

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate local resource directory and manifest invariants."
    )

    @Option(name: .customLong("app-id"), help: "Application identifier.")
    var appId: String

    @Option(name: .customLong("version"), help: "Manifest version to validate.")
    var version: String

    @Option(name: .customLong("resources-dir"), help: "Directory with static resources.")
    var resourcesDir: String

    @Option(name: .customLong("min-sdk-version"), help: "Minimum SDK version in manifest.")
    var minSdkVersion: String = "1.0"

    mutating func run() throws {
        let (resourcesDirURL, resources) = try CLIShared.scanDirectory(resourcesDir)
        _ = try CLIShared.prepareManifest(
            appId: appId,
            version: version,
            minSdkVersion: minSdkVersion,
            resourcesDirURL: resourcesDirURL,
            resources: resources
        )

        print("validate completed")
        print("status: ok")
        print("resources_dir: \(resourcesDirURL.path)")
        print("resources_total: \(resources.count)")
    }
}

struct CleanupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cleanup",
        abstract: "Remove old manifests/patches/resources and keep only latest N versions."
    )

    @Option(name: .customLong("app-id"), help: "Application identifier.")
    var appId: String

    @Option(name: .customLong("keep-last"), help: "How many latest versions to keep. Must be >= 1.")
    var keepLast: Int = 3

    @Option(name: .customLong("public-dir"), help: "Public directory path (contains manifests/ and artifacts/).")
    var publicDir: String = "./Public"

    mutating func run() async throws {
        let trimmedAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAppId.isEmpty {
            throw ValidationError("--app-id must not be empty")
        }
        if keepLast < 1 {
            throw ValidationError("--keep-last must be >= 1")
        }

        let publicURL = URL(fileURLWithPath: publicDir, isDirectory: true).standardizedFileURL
        let storage = ManifestStorage(
            publicDirectory: publicURL.path,
            artifactStorage: LocalArtifactStorage(publicDirectory: publicURL.path)
        )

        let result = try await storage.cleanup(appId: trimmedAppId, keepLast: keepLast)
        print("cleanup completed")
        print("appId: \(trimmedAppId)")
        print("public_dir: \(publicURL.path)")
        print("keep_last: \(keepLast)")
        print("removed_versions: \(result.removedVersions.count)")
        if !result.removedVersions.isEmpty {
            print("removed_versions_list: \(result.removedVersions.joined(separator: ","))")
        }
        print("removed_patch_artifacts: \(result.removedPatchArtifacts)")
        print("removed_resource_binaries: \(result.removedResourceBinaries)")
    }
}

enum CLIShared {
    struct PreparedManifest {
        let resources: [ResourceEntryWithData]
        let manifest: Manifest
    }

    struct PublishReport {
        let uploadedCount: Int
        let skippedCount: Int
        let manifestStatusCode: Int
    }

    static func parseBaseURL(_ value: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw ValidationError("invalid --base-url: \(value)")
        }
        return url
    }

    static func scanDirectory(_ path: String) throws -> (URL, [ResourceEntryWithData]) {
        let resourcesDirURL = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: resourcesDirURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            throw ValidationError("resources directory does not exist: \(resourcesDirURL.path)")
        }

        let resources = try collectResources(in: resourcesDirURL)
        if resources.isEmpty {
            throw ValidationError("resources directory is empty: \(resourcesDirURL.path)")
        }
        return (resourcesDirURL, resources)
    }

    static func prepareManifest(
        appId: String,
        version: String,
        minSdkVersion: String,
        resourcesDirURL: URL,
        resources: [ResourceEntryWithData]
    ) throws -> PreparedManifest {
        let trimmedAppId = appId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAppId.isEmpty {
            throw ValidationError("--app-id must not be empty")
        }
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedVersion.isEmpty {
            throw ValidationError("--version must not be empty")
        }

        let manifest = Manifest(
            schemaVersion: 1,
            minSdkVersion: minSdkVersion,
            version: version,
            generatedAt: Date(),
            resources: resources.map(\.entry)
        )

        return PreparedManifest(resources: resources, manifest: manifest)
    }

    static func publish(
        baseURL: URL,
        token: String,
        appId: String,
        version: String,
        requestId: String,
        resources: [ResourceEntryWithData],
        manifest: Manifest
    ) async throws -> PublishReport {
        var uploaded = 0
        var skipped = 0

        for resource in resources {
            let status = try await uploadResource(
                baseURL: baseURL,
                token: token,
                appId: appId,
                resource: resource
            )
            if status == 201 {
                uploaded += 1
            } else if status == 200 {
                skipped += 1
            } else {
                throw CLIHTTPError("unexpected resource upload status \(status) for \(resource.entry.path)")
            }
        }

        let manifestStatus = try await publishManifest(
            baseURL: baseURL,
            token: token,
            appId: appId,
            version: version,
            requestId: requestId,
            manifest: manifest
        )

        if manifestStatus != 201, manifestStatus != 200 {
            throw CLIHTTPError("unexpected manifest publish status \(manifestStatus)")
        }

        return PublishReport(
            uploadedCount: uploaded,
            skippedCount: skipped,
            manifestStatusCode: manifestStatus
        )
    }

    private static func uploadResource(
        baseURL: URL,
        token: String,
        appId: String,
        resource: ResourceEntryWithData
    ) async throws -> Int {
        var request = URLRequest(url: baseURL.appending(path: "v1/resource/\(appId)/upload"))
        request.httpMethod = "POST"
        request.httpBody = resource.data
        request.setValue(token, forHTTPHeaderField: "X-CI-Token")
        request.setValue(resource.entry.path, forHTTPHeaderField: "X-Resource-Path")
        request.setValue(resource.entry.hash, forHTTPHeaderField: "X-Resource-Hash")
        request.setValue(String(resource.entry.size), forHTTPHeaderField: "X-Resource-Size")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIHTTPError("resource upload response is not HTTP")
        }
        return http.statusCode
    }

    private static func publishManifest(
        baseURL: URL,
        token: String,
        appId: String,
        version: String,
        requestId: String,
        manifest: Manifest
    ) async throws -> Int {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)

        var request = URLRequest(url: baseURL.appending(path: "v1/manifest/\(appId)/version/\(version)"))
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue(token, forHTTPHeaderField: "X-CI-Token")
        request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIHTTPError("manifest publish response is not HTTP")
        }
        if http.statusCode >= 300 {
            let body = String(data: responseData, encoding: .utf8) ?? "<non-utf8>"
            throw CLIHTTPError("manifest publish failed with \(http.statusCode): \(body)")
        }
        return http.statusCode
    }

    private static func collectResources(in directory: URL) throws -> [ResourceEntryWithData] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw ValidationError("failed to read directory: \(directory.path)")
        }

        var resources: [ResourceEntryWithData] = []
        while let fileURL = enumerator.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }

            let data = try Data(contentsOf: fileURL)
            let relativePath = try makeRelativePath(fileURL: fileURL, root: directory)
            let hash = sha256(data)

            let entry = ResourceEntry(
                path: relativePath,
                hash: hash,
                size: data.count
            )
            resources.append(ResourceEntryWithData(entry: entry, data: data))
        }

        resources.sort { $0.entry.path < $1.entry.path }
        return resources
    }

    private static func makeRelativePath(fileURL: URL, root: URL) throws -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            throw ValidationError("resource file is outside root: \(fileURL.path)")
        }
        var relative = String(filePath.dropFirst(rootPath.count))
        while relative.hasPrefix("/") {
            relative.removeFirst()
        }
        if relative.isEmpty {
            throw ValidationError("invalid relative path for \(fileURL.path)")
        }
        return relative
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct ResourceEntryWithData {
    let entry: ResourceEntry
    let data: Data
}

struct CLIHTTPError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        "HTTP error: \(message)"
    }
}
