//
//  ReachabilityStatus.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

public struct ReachabilityStatus: Sendable {

    public enum Status: Sendable {
        case online
        case offline
    }

    public enum ConnectionType: Sendable {
        case wifi
        case mobile
    }

    public enum Restricted: Sendable {
        case no
        case lowDataMode
    }

    public let status: Status
    public let connectionType: ConnectionType
    public let restricted: Restricted

    public init(
        status: Status,
        connectionType: ConnectionType,
        restricted: Restricted
    ) {
        self.status = status
        self.connectionType = connectionType
        self.restricted = restricted
    }
}
