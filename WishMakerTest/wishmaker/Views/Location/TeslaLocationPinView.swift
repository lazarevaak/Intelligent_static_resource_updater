//
//  TeslaLocationPinView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import SwiftUI

struct TeslaLocationPinView: View {
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppColors.color(AppColors.primaryText))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppColors.color(AppColors.mapTeslaBadgeBackground))
                )

            ZStack {
                Circle()
                    .fill(AppColors.color(AppColors.mapTeslaPinBackground))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(AppColors.color(AppColors.mapTeslaPinBorder), lineWidth: 1)
                    )

                Image(systemName: "car.side.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.color(AppColors.primaryText))
            }
            .shadow(color: AppColors.color(AppColors.mapTeslaPinShadow), radius: 12, y: 8)
        }
    }
}
