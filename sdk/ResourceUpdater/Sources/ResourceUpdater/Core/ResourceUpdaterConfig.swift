import Foundation

public struct ResourceUpdaterConfig {
    public let baseURL: URL
    public let appId: String
    public let sdkVersion: String
    public let storageDirectory: URL

    public init(
        baseURL: URL,
        appId: String,
        sdkVersion: String,
        storageDirectory: URL
    ) {
        self.baseURL = baseURL
        self.appId = appId
        self.sdkVersion = sdkVersion
        self.storageDirectory = storageDirectory
    }
}
