//
//  BatteryServiceProtocol.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
public protocol BatteryServiceProtocol: AnyObject, Sendable {
    var currentStatus: BatteryStatus { get async }
}
