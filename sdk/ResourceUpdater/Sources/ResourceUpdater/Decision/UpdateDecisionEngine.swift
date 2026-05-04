import Foundation

public struct UpdateDecision: Equatable, Sendable {
    public let shouldUpdate: Bool
    public let probability: Double?

    public init(shouldUpdate: Bool, probability: Double?) {
        self.shouldUpdate = shouldUpdate
        self.probability = probability
    }
}

public protocol UpdateDecisionEngine: Sendable {
    func evaluate(context: UpdateDecisionContext, isCriticalUpdate: Bool) async -> UpdateDecision
}
