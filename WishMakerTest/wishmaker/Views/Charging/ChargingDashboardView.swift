//
//  ChargingDashboardView.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import SwiftUI
import UIKit

struct ChargingDashboardView: View {
    
    @ObservedObject var viewModel: ChargingDashboardViewModel
    @State private var pulse = false
    @State private var isStationPickerPresented = false
    @State private var isStartPromptPresented = false
    @State private var isStopPromptPresented = false
    @State private var draftChargeLimit: Double = 80
    @State private var previousChargeLimit: Double = 80
    @State private var isEditingChargeLimit = false
    @State private var isChargeLimitConfirmPresented = false

    init(viewModel: ChargingDashboardViewModel) {
        self.viewModel = viewModel
    }

    private var copy: AppCopy { viewModel.copy }
    private var charging: Charging { viewModel.charging }

    var body: some View {
        ZStack {
            chargingBackgroundGradient
            chargingBackgroundGlow

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    heroCard
                    chargingMetrics
                    limitCard
                    controlsCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(ScrollBounceDisabler())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
            let current = Double(charging.chargeLimitPercent)
            draftChargeLimit = current
            previousChargeLimit = current
        }
        .onChange(of: charging.chargeLimitPercent) { _, newValue in
            guard !isEditingChargeLimit else { return }
            let value = Double(newValue)
            draftChargeLimit = value
            previousChargeLimit = value
        }
        .sheet(isPresented: $isStationPickerPresented) {
            ChargingStationPickerView(
                copy: copy,
                stations: viewModel.chargingStations
            ) { station in
                viewModel.selectChargingStation(station)
                isStartPromptPresented = true
            }
        }
        .alert(copy.chargingTitle, isPresented: $isStartPromptPresented) {
            Button(copy.notNow, role: .cancel) {}
            Button(copy.start) { viewModel.startCharging() }
        } message: {
            Text(copy.startChargingPrompt(station: charging.selectedStation?.title ?? ""))
        }
        .alert(copy.changeChargeLimitTitle, isPresented: $isChargeLimitConfirmPresented) {
            Button(copy.notNow, role: .cancel) { draftChargeLimit = previousChargeLimit }
            Button(copy.select) {
                let newValue = Int(draftChargeLimit.rounded())
                viewModel.setChargeLimitPercent(newValue)
                previousChargeLimit = Double(newValue)
            }
        } message: {
            Text(copy.changeChargeLimitMessage)
        }
        .alert(copy.stopChargingConfirmTitle, isPresented: $isStopPromptPresented) {
            Button(copy.notNow, role: .cancel) {}
            Button(copy.stopCharging, role: .destructive) { viewModel.stopCharging() }
        } message: {
            Text(copy.stopChargingConfirmMessage)
        }
        .alert(
            copy.reachedChargeLimitTitle,
            isPresented: Binding(
                get: { viewModel.limitReachedAlertIsPresented },
                set: { viewModel.setLimitReachedAlertPresented($0) }
            )
        ) {
            Button(copy.ok, role: .cancel) {}
        } message: {
            Text(copy.reachedChargeLimitMessage(limit: charging.chargeLimitPercent))
        }
    }

    private var chargingBackgroundGradient: some View {
        AppGradientBackground()
    }

    private var chargingBackgroundGlow: some View {
        ZStack {
            Circle()
                .fill(AppColors.color(AppColors.chargingGlow))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 120, y: -220)

            Circle()
                .fill(AppColors.color(AppColors.chargingAccentSoft))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -140, y: 180)
        }
    }

    private var heroCard: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(copy.chargingTitle)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(AppColors.color(AppColors.primaryText))

                    Button {
                        isStationPickerPresented = true
                    } label: {
                        Text(charging.selectedStation?.title ?? copy.chooseChargingStation)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.color(AppColors.mapOverlaySubtitle))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                    Text(copy.chargingTitle)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(AppColors.color(AppColors.accent))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(AppColors.color(AppColors.chargingStatusBackground))
                        .overlay(
                            Capsule()
                                .stroke(AppColors.color(AppColors.chargingCardBorder), lineWidth: 1)
                        )
                )
            }

            carSilhouette

            ZStack {
                Circle()
                    .stroke(AppColors.color(AppColors.chargingTrack), lineWidth: 16)

                Circle()
                    .trim(from: 0, to: charging.batteryLevel)
                    .stroke(
                        AngularGradient(
                            colors: [
                                AppColors.color(batteryAccentColor),
                                AppColors.color(batteryAccentColor).opacity(0.85),
                                AppColors.color(batteryAccentColor)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: AppColors.color(AppColors.chargingStrongGlow), radius: pulse ? 24 : 14)

                VStack(spacing: 6) {
                    Text(viewModel.batteryPercentText)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(AppColors.color(AppColors.primaryText))

                    Text(viewModel.estimatedRangeText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColors.color(AppColors.mapOverlaySubtitle))
                }
            }
            .frame(width: 200, height: 200)

            HStack(spacing: 12) {
                chargingBadge(title: viewModel.timeUntilFullText, subtitle: copy.untilFull, systemName: "clock")
                chargingBadge(title: viewModel.powerText, subtitle: copy.speed, systemName: "bolt.batteryblock")
            }
        }
        .padding(24)
        .background(glassCard(cornerRadius: 34))
    }

    private var carSilhouette: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(AppColors.color(AppColors.chargingAccentSoft))
                .frame(height: 110)
                .blur(radius: 0.4)

            Image(systemName: "car.side.fill")
                .font(.system(size: 62, weight: .regular))
                .foregroundStyle(AppColors.color(AppColors.primaryText))
                .shadow(color: AppColors.color(AppColors.chargingStrongGlow), radius: 20)
        }
    }

    private var chargingMetrics: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                statCard(
                    title: copy.addedEnergy,
                    value: viewModel.addedEnergyText,
                    systemName: "plus.circle.fill"
                )
                statCard(
                    title: copy.addedRange,
                    value: viewModel.addedRangeText,
                    systemName: "arrow.forward.circle.fill"
                )
            }

            HStack(spacing: 14) {
                statCard(title: copy.cost, value: viewModel.costText, systemName: "eurosign.circle.fill")
                statCard(title: copy.status, value: viewModel.statusText, systemName: "checkmark.circle.fill")
            }
        }
    }

    private var limitCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.chargeLimit)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppColors.color(AppColors.primaryText))

                    Text(copy.chargeProtection)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.color(AppColors.mapOverlaySubtitle))
                }

                Spacer()

                Text(viewModel.chargeLimitText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColors.color(AppColors.accent))
            }

            Slider(value: $draftChargeLimit, in: 50...100, step: 1) { editing in
                isEditingChargeLimit = editing
                if editing {
                    previousChargeLimit = Double(charging.chargeLimitPercent)
                    return
                }

                let newValue = Int(draftChargeLimit.rounded())
                let oldValue = Int(previousChargeLimit.rounded())
                if newValue != oldValue {
                    isChargeLimitConfirmPresented = true
                } else {
                    draftChargeLimit = previousChargeLimit
                }
            }
                .tint(AppColors.color(AppColors.chargingSliderFill))

            HStack {
                Text(viewModel.minimumChargeLimitText)
                Spacer()
                Text(copy.recommendedChargeLimit(charging.chargeLimitPercent))
                Spacer()
                Text(viewModel.maximumChargeLimitText)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(AppColors.color(AppColors.faintText))
        }
        .padding(22)
        .background(glassCard(cornerRadius: 28))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.quickControls)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppColors.color(AppColors.primaryText))

            HStack(spacing: 14) {
                controlTileButton(title: copy.startCharging, systemName: "play.fill", highlighted: true) {
                    if charging.selectedStation == nil {
                        isStationPickerPresented = true
                        return
                    }
                    isStartPromptPresented = true
                }
                controlTileButton(title: copy.stopCharging, systemName: "stop.fill") {
                    guard charging.status == .charging else { return }
                    isStopPromptPresented = true
                }
            }

            HStack(spacing: 14) {
                controlTileButton(title: copy.openChargePort, systemName: "powerplug.fill") {}
                controlTileButton(title: copy.setChargeLimit, systemName: "slider.horizontal.3") {}
            }

            controlTileButton(title: copy.scheduleCharging, systemName: "calendar.badge.clock", expanded: true) {}
        }
        .padding(22)
        .background(glassCard(cornerRadius: 28))
    }

    private func chargingBadge(title: String, subtitle: String, systemName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .foregroundStyle(AppColors.color(AppColors.accent))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.color(AppColors.primaryText))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.color(AppColors.faintText))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.color(AppColors.chargingCardFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AppColors.color(AppColors.chargingCardBorder), lineWidth: 1)
                )
        )
    }

    private func statCard(title: String, value: String, systemName: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.color(AppColors.accent))

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.color(AppColors.primaryText))

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.color(AppColors.mapOverlaySubtitle))
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(18)
        .background(glassCard(cornerRadius: 26))
    }

    private func controlTileButton(
        title: String,
        systemName: String,
        highlighted: Bool = false,
        expanded: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppColors.color(highlighted ? AppColors.accent : AppColors.chargingButtonFill))
                        .frame(width: 42, height: 42)

                    Image(systemName: systemName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(
                            AppColors.color(highlighted ? AppColors.appBackground : AppColors.primaryText)
                        )
                }

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.color(AppColors.primaryTextMuted))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.78)
                    .allowsTightening(true)
                    .layoutPriority(1)

                Spacer()
            }
            .frame(maxWidth: expanded ? .infinity : .infinity, minHeight: 76, alignment: .leading)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppColors.color(AppColors.chargingButtonFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                AppColors.color(highlighted ? AppColors.chargingStrongGlow : AppColors.chargingButtonBorder),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: highlighted ? AppColors.color(AppColors.chargingGlow) : .clear,
                radius: highlighted ? 16 : 0,
                y: 8
            )
        }
        .buttonStyle(.plain)
    }

    private func glassCard(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppColors.color(AppColors.chargingCardFill))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.color(AppColors.chargingCardBorder), lineWidth: 1)
            )
            .shadow(color: AppColors.color(AppColors.chargingGlow), radius: 24, y: 12)
    }

    private var batteryAccentColor: UIColor {
        switch viewModel.batteryLevelState {
        case .critical:
            return AppColors.chargingBatteryCritical
        case .medium:
            return AppColors.chargingBatteryMid
        case .good:
            return AppColors.chargingBatteryGood
        }
    }
}

private struct ScrollBounceDisabler: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        disableBounce(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        disableBounce(from: uiView)
    }

    private func disableBounce(from view: UIView) {
        DispatchQueue.main.async {
            sequence(first: view.superview, next: { $0?.superview })
                .first(where: { $0 is UIScrollView })
                .flatMap { $0 as? UIScrollView }?
                .bounces = false
        }
    }
}

#Preview {
    ChargingDashboardView(
        viewModel: ChargingDashboardViewModel(
            appState: AppState(),
            locationRepository: StaticLocationRepository()
        )
    )
}
