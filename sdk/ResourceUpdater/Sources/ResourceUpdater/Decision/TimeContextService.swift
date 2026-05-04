//
//  TimeContextService.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

public struct TimeContext: Equatable, Sendable {
    public let hourOfDay: Int
    public let isNightTime: Bool

    public init(hourOfDay: Int, isNightTime: Bool) {
        self.hourOfDay = hourOfDay
        self.isNightTime = isNightTime
    }
}

public protocol TimeContextServiceProtocol: Sendable {
    func currentContext(at date: Date) -> TimeContext
}

public struct TimeContextService: TimeContextServiceProtocol {
    public init() {}

    public func currentContext(at date: Date = Date()) -> TimeContext {
        TimeContextMapper().map(date: date)
    }
}

public struct TimeContextMapper: Sendable {
    public init() {}

    public func map(date: Date, calendar: Calendar = .current) -> TimeContext {
        let hour = calendar.component(.hour, from: date)
        return TimeContext(hourOfDay: hour, isNightTime: hour < 7 || hour >= 23)
    }
}
