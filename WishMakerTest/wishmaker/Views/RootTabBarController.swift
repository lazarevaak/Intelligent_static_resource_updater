//
//  RootTabBarController.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import UIKit

@MainActor
final class RootTabBarController: UITabBarController {
    private enum Layout {
        static let tabBarHorizontalInset: CGFloat = 16
        static let tabBarBottomInset: CGFloat = 10
        static let tabBarHeight: CGFloat = 74
        static let tabBarContentInset: CGFloat = 24
    }

    private let iconProvider: TabBarIconProvider

    init(viewControllers: [UIViewController]) {
        self.iconProvider = .shared
        super.init(nibName: nil, bundle: nil)
        configureTabBarItems(for: viewControllers)
        self.viewControllers = viewControllers
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTabBar()
        applyIcons()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTabBar()
        layoutTabBarButtons()
    }

    private func configureTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.tabBarBackground
        appearance.shadowColor = .clear

        let normalColor = AppColors.iconTint
        let selectedColor = AppColors.primaryText

        [appearance.stackedLayoutAppearance,
         appearance.inlineLayoutAppearance,
         appearance.compactInlineLayoutAppearance].forEach { itemAppearance in
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
            itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.clear]
        }

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = selectedColor
        tabBar.unselectedItemTintColor = normalColor
        tabBar.layer.cornerRadius = 28
        tabBar.layer.masksToBounds = false
        tabBar.itemPositioning = .automatic
        tabBar.itemWidth = 44
    }

    private func layoutTabBar() {
        let safeAreaBottom = view.safeAreaInsets.bottom
        var frame = tabBar.frame
        frame.size.height = Layout.tabBarHeight + safeAreaBottom
        frame.size.width = view.bounds.width - (Layout.tabBarHorizontalInset * 2)
        frame.origin.x = Layout.tabBarHorizontalInset
        frame.origin.y = view.bounds.height - frame.height - Layout.tabBarBottomInset
        tabBar.frame = frame
    }

    private func layoutTabBarButtons() {
        let buttonClass: AnyClass? = NSClassFromString("UITabBarButton")
        let buttons = tabBar.subviews
            .filter { subview in
                guard let buttonClass else { return false }
                return subview.isKind(of: buttonClass)
            }
            .sorted { $0.frame.minX < $1.frame.minX }

        guard buttons.count == (tabBar.items?.count ?? 0), !buttons.isEmpty else {
            return
        }

        let contentMinX = Layout.tabBarContentInset
        let contentMaxX = tabBar.bounds.width - Layout.tabBarContentInset
        position(buttons: buttons, from: contentMinX, to: contentMaxX)
    }

    private func position(buttons: [UIView], from minX: CGFloat, to maxX: CGFloat) {
        guard !buttons.isEmpty else { return }

        let slotWidth = (maxX - minX) / CGFloat(buttons.count)

        for (index, button) in buttons.enumerated() {
            var frame = button.frame
            frame.origin.x = minX + (slotWidth * CGFloat(index))
            frame.size.width = slotWidth
            button.frame = frame
        }
    }

    private func applyIcons() {
        let icons = iconProvider.makeIconSet()
        let items = tabBar.items ?? []
        let iconImages = [icons.list, icons.bolt, icons.location, icons.profile]

        for (index, item) in items.enumerated() where index < iconImages.count {
            item.title = nil
            item.image = iconImages[index]
            item.selectedImage = iconImages[index]
            item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
        }
    }

    private func configureTabBarItems(for viewControllers: [UIViewController]) {
        let icons = iconProvider.makeIconSet()
        let iconImages = [icons.list, icons.bolt, icons.location, icons.profile]

        for (index, controller) in viewControllers.enumerated() where index < iconImages.count {
            let item = UITabBarItem(title: nil, image: iconImages[index], selectedImage: iconImages[index])
            item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
            controller.tabBarItem = item
        }
    }
}
