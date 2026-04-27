import Foundation
import ResourceUpdater

struct SliderLabels: Decodable {
    let red: String
    let green: String
    let blue: String

    static let fallback = SliderLabels(
        red: "Red",
        green: "Green",
        blue: "Blue"
    )
}

final class RemoteSliderLabelService {
    static let shared = RemoteSliderLabelService()

    private enum Constants {
        static let baseURL = "http://127.0.0.1:8081/"
        static let appID = "demoapp"
        static let sdkVersion = "1.0"
        static let resourcePath = "texts/slider-labels.json"
    }

    private let updater: ResourceUpdater
    private let storageDirectory: URL
    private let decoder = JSONDecoder()

    private init() {
        let storageDirectory = Self.makeStorageDirectory()
        self.storageDirectory = storageDirectory
        self.updater = ResourceUpdater(
            config: ResourceUpdaterConfig(
                baseURL: URL(string: Constants.baseURL)!,
                appId: Constants.appID,
                sdkVersion: Constants.sdkVersion,
                storageDirectory: storageDirectory
            )
        )
    }

    func currentLabels() -> SliderLabels {
        let fileURL = storageDirectory
            .appendingPathComponent("resources", isDirectory: true)
            .appendingPathComponent(Constants.resourcePath)

        guard let data = try? Data(contentsOf: fileURL),
              let labels = try? decoder.decode(SliderLabels.self, from: data) else {
            return .fallback
        }

        return labels
    }

    @discardableResult
    func syncLabels() async throws -> SliderLabels {
        try await updater.applyUpdates()
        return currentLabels()
    }

    private static func makeStorageDirectory() -> URL {
        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseDirectory.appendingPathComponent("resource-updater-demo", isDirectory: true)
    }
}
