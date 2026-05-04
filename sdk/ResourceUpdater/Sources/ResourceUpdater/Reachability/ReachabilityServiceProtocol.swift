//
//  ReachabilityServiceProtocol.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
public protocol ReachabilityServiceProtocol: AnyObject, Sendable {
    var currentStatus: ReachabilityStatus { get async }
    var statusStream: AsyncStream<ReachabilityStatus> { get async }
}
