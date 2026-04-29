//
//  TabContentContainerViewController.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.
//

import UIKit

@MainActor
final class TabContentContainerViewController: UIViewController {
    private let contentController: UIViewController
    private var bottomConstraint: NSLayoutConstraint?

    var contentBottomInset: CGFloat = 0 {
        didSet {
            bottomConstraint?.constant = -contentBottomInset
        }
    }

    init(contentController: UIViewController) {
        self.contentController = contentController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        embedContentController()
    }

    private func embedContentController() {
        addChild(contentController)
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentController.view)

        let bottomConstraint = contentController.view.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -contentBottomInset
        )
        self.bottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            contentController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint
        ])

        contentController.didMove(toParent: self)
    }
}
