import CoreML
import Foundation

public actor MLUpdateDecisionEngine: UpdateDecisionEngine {
    public static let shared = MLUpdateDecisionEngine()

    private var model: MLModel?

    public init() {}

    public func evaluate(context: UpdateDecisionContext, isCriticalUpdate: Bool) async -> UpdateDecision {
        do {
            let mlModel = try await loadModelIfNeeded()
            let input = try makeFeatures(context: context, isCriticalUpdate: isCriticalUpdate)
            let output = try mlModel.prediction(from: input)

            let shouldUpdate = output.featureValue(for: "shouldUpdate")?.int64Value ?? 0
            let probabilityDict = output.featureValue(for: "shouldUpdateProbability")?.dictionaryValue as? [Int64: NSNumber]
            let p = probabilityDict?[1]?.doubleValue

            return UpdateDecision(shouldUpdate: shouldUpdate == 1, probability: p)
        } catch {
            // Fail open: if ML is unavailable, do not block updates.
            return UpdateDecision(shouldUpdate: true, probability: nil)
        }
    }

    private func loadModelIfNeeded() async throws -> MLModel {
        if let model { return model }

        let url = try modelURL()
        let loaded: MLModel
        if url.pathExtension == "mlmodelc" {
            loaded = try MLModel(contentsOf: url)
        } else {
            let compiledURL = try MLModel.compileModel(at: url)
            loaded = try MLModel(contentsOf: compiledURL)
        }
        model = loaded
        return loaded
    }

    private func modelURL() throws -> URL {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "ResourceUpdateDecision", withExtension: "mlmodel") {
            return url
        }
        if let url = Bundle.module.url(forResource: "ResourceUpdateDecision", withExtension: "mlmodelc") {
            return url
        }
        #endif

        throw NSError(domain: "ResourceUpdater.ML", code: 1, userInfo: [NSLocalizedDescriptionKey: "ResourceUpdateDecision model not found"])
    }

    private func makeFeatures(context: UpdateDecisionContext, isCriticalUpdate: Bool) throws -> MLFeatureProvider {
        let networkType = encodeNetworkType(context: context)
        let battery = context.batteryLevel ?? 0.5

        let dict: [String: MLFeatureValue] = [
            "networkType": MLFeatureValue(int64: networkType),
            "batteryLevel": MLFeatureValue(double: battery),
            "isCharging": MLFeatureValue(int64: context.isCharging ? 1 : 0),
            "updateSizeMb": MLFeatureValue(double: context.updateSizeMb),
            "usageFrequency": MLFeatureValue(double: context.usageFrequency),
            "isCriticalUpdate": MLFeatureValue(int64: isCriticalUpdate ? 1 : 0)
        ]

        return try MLDictionaryFeatureProvider(dictionary: dict)
    }

    private func encodeNetworkType(context: UpdateDecisionContext) -> Int64 {
        // Matches training dataset: 0=wifi, 1=mobile, 2=offline/unknown.
        if !context.isOnline { return 2 }
        switch context.networkType.lowercased() {
        case "wifi":
            return 0
        case "mobile":
            return 1
        default:
            return 2
        }
    }
}
