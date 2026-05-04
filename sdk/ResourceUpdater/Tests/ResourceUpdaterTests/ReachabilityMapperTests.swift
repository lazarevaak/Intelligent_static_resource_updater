//
//  ReachabilityMapperTests.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
//

import Network
import Testing

@testable import ResourceUpdater

struct ReachabilityMapperTests {
    let mapper = ReachabilityMapper()

    @Test func offlineMobileNotConstrained() {
        let result = mapper.map(
            status: .unsatisfied,
            isWifi: false,
            isConstrained: false
        )

        #expect(result.status == .offline)
        #expect(result.connectionType == .mobile)
        #expect(result.restricted == .no)
    }

    @Test func onlineWifiConstrained() {
        let result = mapper.map(
            status: .satisfied,
            isWifi: true,
            isConstrained: true
        )

        #expect(result.status == .online)
        #expect(result.connectionType == .wifi)
        #expect(result.restricted == .lowDataMode)
    }

    @Test func onlineMobileNotConstrained() {
        let result = mapper.map(
            status: .satisfied,
            isWifi: false,
            isConstrained: false
        )

        #expect(result.status == .online)
        #expect(result.connectionType == .mobile)
        #expect(result.restricted == .no)
    }
}
