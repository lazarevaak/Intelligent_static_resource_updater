//
//  AppGradientBackgroundView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 29.04.2026.

import QuartzCore
import SwiftUI
import UIKit

@MainActor
final class GradientBackgroundView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureGradient()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    private func configureGradient() {
        gradientLayer.colors = [
            AppColors.gradientStart.cgColor,
            AppColors.gradientMiddle.cgColor,
            AppColors.gradientEnd.cgColor
        ]
        
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        
        layer.addSublayer(gradientLayer)
    }
}

private struct GradientBackgroundRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> GradientBackgroundView {
        GradientBackgroundView()
    }

    func updateUIView(_ uiView: GradientBackgroundView, context: Context) {}
}

struct AppGradientBackground: View {
    var body: some View {
        GradientBackgroundRepresentable()
            .ignoresSafeArea()
    }
}
