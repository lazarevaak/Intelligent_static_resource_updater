//
//  ProfileDashboardView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import SwiftUI

struct ProfileDashboardView: View {
    
    @ObservedObject var viewModel: ProfileDashboardViewModel
    @State private var isAvatarPickerPresented = false
    @State private var isVehiclePickerPresented = false

    @Environment(\.dismiss) private var dismiss
    @State private var hasDismissed = false

    private var user: AppUser { viewModel.user }
    private var vehicle: TeslaVehicle? { viewModel.vehicle }
    private var copy: AppCopy { viewModel.copy }

    init(viewModel: ProfileDashboardViewModel, dismissOnPullDown: Bool = false) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack {
            AppGradientBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerCard
                    statsCard
                    actionsCard
                    vehiclesCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 132)
            }
        }
        .sheet(isPresented: $isAvatarPickerPresented) {
            AvatarPickerSheetView(
                copy: copy,
                selectedAvatar: user.avatarSymbolName,
                options: avatarOptions,
                onSelect: { symbolName in
                    viewModel.setAvatar(symbolName: symbolName)
                }
            )
        }
        .sheet(isPresented: $isVehiclePickerPresented) {
            VehiclePickerSheetView(
                copy: copy,
                vehicles: viewModel.availableVehicles,
                onBind: { selectedVehicle in
                    viewModel.bindVehicle(selectedVehicle)
                }
            )
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.profileTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppColors.color(AppColors.primaryText))

                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AppColors.color(AppColors.premiumBadge))
                        Text(copy.premiumDriver)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(AppColors.color(AppColors.subduedText))
                    }
                }

                Spacer()

                Button {
                    isAvatarPickerPresented = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(AppColors.color(AppColors.controlBackground))
                            .frame(width: 58, height: 58)
                            .overlay(
                                Circle()
                                    .stroke(AppColors.color(AppColors.elevatedBorder), lineWidth: 1)
                            )

                        Image(systemName: user.avatarSymbolName)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(AppColors.color(AppColors.mutedText))
                    }
                    .shadow(color: AppColors.color(AppColors.profileShadow), radius: 18, y: 8)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                profileMetric(title: copy.trips, value: "\(vehicle?.profile.tripsCount ?? 0)")
                profileMetric(title: copy.rating, value: String(format: "%.1f", vehicle?.profile.rating ?? 0))
                profileMetric(title: copy.energy, value: "\(vehicle?.batteryPercent ?? 0)%")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(copy.preferences)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.color(AppColors.tertiaryText))

                HStack(spacing: 12) {
                    if let vehicle {
                        ForEach(Array(vehicle.profile.preferences.enumerated()), id: \.offset) { index, preference in
                            capsuleButton(
                                title: preferenceTitle(for: index),
                                action: preference
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(cardBackground(cornerRadius: 34))
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(copy.overview)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.color(AppColors.primaryText))

            profileRow(systemName: "bolt.fill", title: copy.chargeTarget, subtitle: "\(vehicle?.chargeLimitPercent ?? 80)%")
            profileRow(systemName: "location.north.fill", title: copy.homeCharging, subtitle: vehicle?.charging.locationName ?? copy.noCarsBound)
            profileRow(systemName: "lock.shield.fill", title: copy.security, subtitle: copy.faceIdEnabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(cardBackground(cornerRadius: 30))
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.quickActions)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(AppColors.color(AppColors.primaryText))

            HStack(spacing: 14) {
                actionTile(title: copy.control, systemName: quickActionSystemName(at: 0, fallback: "car.fill"))
                actionTile(title: copy.climate, systemName: quickActionSystemName(at: 1, fallback: "fanblades.fill"))
            }

            HStack(spacing: 14) {
                actionTile(title: copy.tripsAction, systemName: quickActionSystemName(at: 2, fallback: "map.fill"))
                actionTile(title: copy.account, systemName: quickActionSystemName(at: 3, fallback: "person.crop.circle.fill"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(cardBackground(cornerRadius: 30))
    }

    private var vehiclesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(copy.cars)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.color(AppColors.primaryText))

                Spacer()

                Button(copy.addCar) {
                    isVehiclePickerPresented = true
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.color(AppColors.accent))
            }

            if user.vehicles.isEmpty {
                Text(copy.noCarsBound)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.color(AppColors.subtitleText))
            } else {
                VStack(spacing: 12) {
                    ForEach(user.vehicles) { car in
                        Button {
                            viewModel.selectVehicle(id: car.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(car.displayName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(AppColors.color(AppColors.primaryText))
                                    Text("\(car.currentRangeKm) km")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(AppColors.color(AppColors.subtitleText))
                                }

                                Spacer()

                                if car.id == vehicle?.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColors.color(AppColors.accent))
                                }
                            }
                            .padding(14)
                            .background(AppColors.color(AppColors.tileFill))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(cardBackground(cornerRadius: 30))
    }

    private func profileMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.color(AppColors.primaryText))
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.color(AppColors.subtitleText))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.color(AppColors.tileFill))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func capsuleButton(title: String, action: VehicleQuickAction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.systemName)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(capsuleAccent(for: action.tintStyle))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.color(AppColors.tileFill))
        .clipShape(Capsule())
    }

    private func profileRow(systemName: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemName)
                .frame(width: 24)
                .foregroundStyle(AppColors.color(AppColors.overlayText))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.color(AppColors.secondaryTextStrong))
                Text(subtitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppColors.color(AppColors.disabledText))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(AppColors.color(AppColors.placeholderTint))
        }
    }

    private func capsuleAccent(for tintStyle: VehicleQuickAction.TintStyle) -> Color {
        switch tintStyle {
        case .accent:
            return AppColors.color(AppColors.premiumBadge)
        case .muted:
            return AppColors.color(AppColors.faintText)
        case .neutral:
            return AppColors.color(AppColors.primaryTextMuted)
        }
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColors.color(AppColors.cardFill))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.color(AppColors.cardBorder), lineWidth: 1)
            )
    }

    private func actionTile(title: String, systemName: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppColors.color(AppColors.actionIcon))

            Spacer()

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.color(AppColors.primaryTextMuted))
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(18)
        .background(AppColors.color(AppColors.tileFill))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func quickActionSystemName(at index: Int, fallback: String) -> String {
        guard let vehicle, vehicle.profile.quickActions.indices.contains(index) else {
            return fallback
        }

        return vehicle.profile.quickActions[index].systemName
    }

    private var avatarOptions: [String] {
        viewModel.avatarOptions
    }

    private func preferenceTitle(for index: Int) -> String {
        switch index {
        case 0:
            return copy.autopilot
        case 1:
            return copy.climate
        default:
            return copy.preferenceGeneric
        }
    }

    private struct PullDownDismissSentinel: View {
        var body: some View {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: PullDownOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("profile_scroll")).minY
                    )
            }
            .frame(height: 0)
        }
    }

    private struct PullDownOffsetPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0

        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}

#Preview {
    ProfileDashboardView(
        viewModel: ProfileDashboardViewModel(
            appState: AppState(),
            avatarOptionsRepository: StaticAvatarOptionsRepository()
        )
    )
}
