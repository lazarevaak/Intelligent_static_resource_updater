//
//  FavoriteLocationsSheetView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import SwiftUI

struct FavoriteLocationsSheetView: View {
    
    let copy: AppCopy
    let locations: [AppLocation]
    let onSelect: (AppLocation) -> Void
    let onToggleFavorite: (AppLocation) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.color(AppColors.appBackground)
                    .ignoresSafeArea()

                if locations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "heart")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(AppColors.color(AppColors.mapCardMeta))

                        Text(copy.noFavoritePlaces)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppColors.color(AppColors.primaryText))

                        Text(copy.addFavoritesHint)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.color(AppColors.mapCardSubtitle))
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                } else {
                    List(locations) { location in
                        HStack(spacing: 12) {
                            Button {
                                dismiss()
                                onSelect(location)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: location.type.iconName)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(AppColors.color(AppColors.primaryText))
                                        .frame(width: 38, height: 38)
                                        .background(
                                            Circle()
                                                .fill(AppColors.color(AppColors.accent))
                                        )

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(location.title)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(AppColors.color(AppColors.primaryText))

                                        Text(location.address)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(AppColors.color(AppColors.mapCardSubtitle))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                onToggleFavorite(location)
                            } label: {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(AppColors.color(AppColors.favoriteRed))
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(AppColors.color(AppColors.appBackground))
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle(copy.favoritesTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copy.close) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
