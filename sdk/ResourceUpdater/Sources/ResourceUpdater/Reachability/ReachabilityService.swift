//
//  ReachabilityService.swift
//  ResourceUpdater
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation
import Network

public final actor ReachabilityService: ReachabilityServiceProtocol {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let mapper: ReachabilityMapper

    private let (stream, continuation) = AsyncStream<ReachabilityStatus>.makeStream()

    public var currentStatus = ReachabilityStatus(
        status: .online,
        connectionType: .wifi,
        restricted: .no
    )

    public var statusStream: AsyncStream<ReachabilityStatus> {
        get async { stream }
    }

    public init(
        monitor: NWPathMonitor = NWPathMonitor(),
        queue: DispatchQueue = DispatchQueue(label: "ResourceUpdater.reachability.monitor", qos: .userInitiated),
        mapper: ReachabilityMapper = ReachabilityMapper()
    ) {
        self.monitor = monitor
        self.queue = queue
        self.mapper = mapper

        Task { await self.startMonitoring() }
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }

    private func startMonitoring() {
        monitor.pathUpdateHandler = { path in
            let status = self.mapper.map(
                status: path.status,
                isWifi: path.usesInterfaceType(.wifi),
                isConstrained: path.isConstrained
            )

            Task { await self.yield(status: status) }
        }

        monitor.start(queue: queue)
    }

    private func yield(status: ReachabilityStatus) {
        currentStatus = status
        continuation.yield(status)
    }
}
