//
//  SceneDelegate.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var appCoordinator: AppCoordinator?
    private let resourceUpdateTimeoutNanoseconds: UInt64 = 2_500_000_000
    private let resourceRefreshIntervalNanoseconds: UInt64 = 10_000_000_000
    private var resourceRefreshTask: Task<Void, Never>?

    private enum ResourceUpdateStartupResult {
        case completed
        case timedOut
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)

        window.rootViewController = LoadingViewController()
        window.makeKeyAndVisible()

        self.window = window

        Task { @MainActor in
            await applyResourceUpdatesBeforeStart()
            applyLoadedResources()

            let coordinator = AppCoordinator()
            appCoordinator = coordinator
            coordinator.prepareForStart()

            try? await Task.sleep(nanoseconds: 500_000_000)

            let rootViewController = coordinator.start()
            UIView.transition(
                with: window,
                duration: 0.28,
                options: [.transitionCrossDissolve, .allowAnimatedContent],
                animations: {
                    window.rootViewController = rootViewController
                },
                completion: nil
            )
            startResourceRefreshLoop()
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        startResourceRefreshLoop()
        Task { @MainActor [weak self] in
            await self?.refreshRemoteResources()
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        stopResourceRefreshLoop()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        stopResourceRefreshLoop()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        appCoordinator?.refreshAfterForeground()
    }

    private func startResourceRefreshLoop() {
        guard resourceRefreshTask == nil else { return }

        let interval = resourceRefreshIntervalNanoseconds
        resourceRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled else { break }
                await self?.refreshRemoteResources()
            }
        }
    }

    private func stopResourceRefreshLoop() {
        resourceRefreshTask?.cancel()
        resourceRefreshTask = nil
    }

    private func refreshRemoteResources() async {
        let didApplyUpdates = await ResourceUpdaterService.shared.applyUpdates()
        guard didApplyUpdates else { return }
        applyLoadedResources()
    }

    private func applyLoadedResources() {
        AppResourceProvider.shared.reloadCachedResources()
        Localization.resetCache()
        ThemeProvider.shared.reloadTheme()
        AppIconService.shared.applyConfiguredIcon()
        appCoordinator?.refreshResources()
    }

    private func applyResourceUpdatesBeforeStart() async {
        let result = await withTaskGroup(of: ResourceUpdateStartupResult.self) { group in
            group.addTask {
                _ = await ResourceUpdaterService.shared.applyUpdates()
                return .completed
            }
            group.addTask { [resourceUpdateTimeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: resourceUpdateTimeoutNanoseconds)
                return .timedOut
            }

            let result = await group.next() ?? ResourceUpdateStartupResult.timedOut
            group.cancelAll()
            return result
        }

        if result == .timedOut {
            AppLogger.resources.warning("Resource update startup timed out")
        }
    }
}
