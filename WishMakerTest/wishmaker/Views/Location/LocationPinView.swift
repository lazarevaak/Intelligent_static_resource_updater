//
//  LocationPinView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import SwiftUI

struct LocationPinView: View {
    let type: LocationType
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? AppColors.color(AppColors.accent) : AppColors.color(AppColors.mapPinBackground))
                .frame(width: 46, height: 46)
                .overlay(
                    Circle()
                        .stroke(AppColors.color(AppColors.mapPinBorder), lineWidth: 1)
                )

            Image(systemName: type.iconName)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(AppColors.color(isSelected ? AppColors.primaryText : AppColors.mapPinIcon))
        }
        .shadow(color: AppColors.color(AppColors.mapPinShadow), radius: 10, y: 6)
    }
}
