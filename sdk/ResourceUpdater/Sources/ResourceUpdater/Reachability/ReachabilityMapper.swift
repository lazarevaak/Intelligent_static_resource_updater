//
//  ReachabilityMapper.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Network

public struct ReachabilityMapper: Sendable {
    // swiftlint:disable:next no_empty_block
    public init() {}

    func map(
        status: NWPath.Status,
        isWifi: Bool,
        isConstrained: Bool
    ) -> ReachabilityStatus {
        ReachabilityStatus(
            status: status == .satisfied ? .online : .offline,
            connectionType: isWifi ? .wifi : .mobile,
            restricted: isConstrained ? .lowDataMode : .no
        )
    }
}
