//
//  TimeContextServiceTests.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
//

import Foundation
import Testing

@testable import ResourceUpdater

struct TimeContextServiceTests {
    let mapper = TimeContextMapper()

    @Test func daytimeIsNotNightTime() {
        let context = mapper.map(date: makeDate(hour: 14), calendar: calendar)

        #expect(context.hourOfDay == 14)
        #expect(!context.isNightTime)
    }

    @Test func lateEveningIsNightTime() {
        let context = mapper.map(date: makeDate(hour: 23), calendar: calendar)

        #expect(context.hourOfDay == 23)
        #expect(context.isNightTime)
    }

    @Test func earlyMorningIsNightTime() {
        let context = mapper.map(date: makeDate(hour: 6), calendar: calendar)

        #expect(context.hourOfDay == 6)
        #expect(context.isNightTime)
    }
}

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func makeDate(hour: Int) -> Date {
    DateComponents(
        calendar: calendar,
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026,
        month: 4,
        day: 27,
        hour: hour
    ).date!
}
