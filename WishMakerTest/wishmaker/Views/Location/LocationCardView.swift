//
//  LocationCardView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import SwiftUI

struct LocationCardView: View {
    let location: AppLocation
    let isSelected: Bool
    let isFavorite: Bool
    let onFavoriteTap: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppColors.color(isSelected ? AppColors.accent : AppColors.mapCardIconBackground))
                        .frame(width: 40, height: 40)

                    Image(systemName: location.type.iconName)
                        .foregroundStyle(AppColors.color(AppColors.primaryText))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(location.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppColors.color(AppColors.primaryText))
                        .lineLimit(1)

                    Text(location.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.color(AppColors.mapCardSubtitle))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: onFavoriteTap) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isFavorite ? AppColors.color(AppColors.favoriteRed) : AppColors.color(AppColors.mapCardMeta))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(AppColors.color(AppColors.mapOverlayButtonBackground))
                        )
                }
                .buttonStyle(.plain)
            }

            Text(location.address)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.color(AppColors.mapCardSubtitle))
                .lineLimit(1)

            HStack(spacing: 14) {
                if let workingHours = location.workingHours {
                    Label(workingHours, systemImage: "clock")
                }

                if let distanceKm = location.distanceKm {
                    Label("\(distanceKm.formatted(.number.precision(.fractionLength(1)))) km", systemImage: "location")
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppColors.color(AppColors.mapCardMeta))
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.color(AppColors.mapCardBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AppColors.color(isSelected ? AppColors.mapCardSelectedBorder : AppColors.mapCardBorder),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: AppColors.color(AppColors.mapCardShadow), radius: 16, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onTap)
    }
}
