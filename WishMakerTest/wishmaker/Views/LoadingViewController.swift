//
//  LoadingViewController.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import UIKit

final class LoadingViewController: UIViewController {
    private let gradientView = GradientBackgroundView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let titleLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureGradient()
        configureContent()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        spinner.startAnimating()
    }

    private func configureGradient() {
        view.backgroundColor = AppColors.appBackground
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gradientView)

        NSLayoutConstraint.activate([
            gradientView.topAnchor.constraint(equalTo: view.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureContent() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.color = AppColors.primaryText

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = AppCopy(language: .system).appTitle
        titleLabel.textColor = AppColors.primaryTextMuted
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)

        view.addSubview(titleLabel)
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -18),

            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16)
        ])
    }
}
