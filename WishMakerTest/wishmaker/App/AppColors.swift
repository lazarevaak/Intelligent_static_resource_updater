//
//  AppColors.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import SwiftUI
import UIKit

@MainActor
enum AppColors {
    static var appBackground: UIColor { color("appBackground", fallback: "#000000") }
    static var gradientStart: UIColor { color("gradientStart", fallback: "#0D0F17") }
    static var gradientMiddle: UIColor { color("gradientMiddle", fallback: "#141418") }
    static var gradientEnd: UIColor { color("gradientEnd", fallback: "#08080D") }
    static var primaryText: UIColor { color("primaryText", fallback: "#FFFFFF") }
    static var accent: UIColor { color("accent", fallback: "#73E6FF") }

    static var plainWhite: UIColor { color("plainWhite", fallback: "#FFFFFF") }
    static var tabBarBackground: UIColor { color("tabBarBackground", fallback: "#FA0D0D0D") }
    static var quickActionsBackground: UIColor { color("quickActionsBackground", fallback: "#F2242424") }
    static var cardBackground: UIColor { color("cardBackground", fallback: "#EB292929") }
    static var cardBorder: UIColor { color("cardBorder", fallback: "#0DFFFFFF") }
    static var elevatedBorder: UIColor { color("elevatedBorder", fallback: "#0FFFFFFF") }
    static var controlBackground: UIColor { color("controlBackground", fallback: "#0DFFFFFF") }
    static var primaryTextMuted: UIColor { color("primaryTextMuted", fallback: "#E6FFFFFF") }
    static var secondaryTextStrong: UIColor { color("secondaryTextStrong", fallback: "#E0FFFFFF") }
    static var secondaryText: UIColor { color("secondaryText", fallback: "#DBFFFFFF") }
    static var tertiaryText: UIColor { color("tertiaryText", fallback: "#D9FFFFFF") }
    static var mutedText: UIColor { color("mutedText", fallback: "#B8FFFFFF") }
    static var hintText: UIColor { color("hintText", fallback: "#A6FFFFFF") }
    static var iconTint: UIColor { color("iconTint", fallback: "#99FFFFFF") }
    static var overlayText: UIColor { color("overlayText", fallback: "#94FFFFFF") }
    static var rangeText: UIColor { color("rangeText", fallback: "#85FFFFFF") }
    static var subduedText: UIColor { color("subduedText", fallback: "#80FFFFFF") }
    static var subtitleText: UIColor { color("subtitleText", fallback: "#73FFFFFF") }
    static var disabledText: UIColor { color("disabledText", fallback: "#6BFFFFFF") }
    static var inactiveTint: UIColor { color("inactiveTint", fallback: "#61FFFFFF") }
    static var faintText: UIColor { color("faintText", fallback: "#59FFFFFF") }
    static var chevronTint: UIColor { color("chevronTint", fallback: "#52FFFFFF") }
    static var placeholderTint: UIColor { color("placeholderTint", fallback: "#40FFFFFF") }

    static var cardFill: UIColor { color("cardFill", fallback: "#14FFFFFF") }
    static var tileFill: UIColor { color("tileFill", fallback: "#0AFFFFFF") }
    static var profileShadow: UIColor { color("profileShadow", fallback: "#1FFFFFFF") }

    static var accentStrong: UIColor { color("accentStrong", fallback: "#5EE0FF") }
    static var accentShadow: UIColor { color("accentShadow", fallback: "#73E6FF") }
    static var favoriteRed: UIColor { color("favoriteRed", fallback: "#EBFF3B30") }
    static var premiumBadge: UIColor { color("premiumBadge", fallback: "#F200C7FF") }
    static var actionIcon: UIColor { color("actionIcon", fallback: "#EB00C7FF") }

    static var mapOverlayBackground: UIColor { color("mapOverlayBackground", fallback: "#D1191919") }
    static var mapOverlayBorder: UIColor { color("mapOverlayBorder", fallback: "#1AFFFFFF") }
    static var mapOverlaySubtitle: UIColor { color("mapOverlaySubtitle", fallback: "#B8FFFFFF") }
    static var mapOverlayButtonBackground: UIColor { color("mapOverlayButtonBackground", fallback: "#1AFFFFFF") }
    static var mapFilterBackground: UIColor { color("mapFilterBackground", fallback: "#D6191919") }
    static var mapFilterSelected: UIColor { color("mapFilterSelected", fallback: "#E0000000") }
    static var mapFilterBorder: UIColor { color("mapFilterBorder", fallback: "#1FFFFFFF") }
    static var mapFilterText: UIColor { color("mapFilterText", fallback: "#D1FFFFFF") }
    static var mapCardBackground: UIColor { color("mapCardBackground", fallback: "#EB1C1C1C") }
    static var mapCardBorder: UIColor { color("mapCardBorder", fallback: "#14FFFFFF") }
    static var mapCardSelectedBorder: UIColor { color("mapCardSelectedBorder", fallback: "#8C73E6FF") }
    static var mapCardShadow: UIColor { color("mapCardShadow", fallback: "#33000000") }
    static var mapCardSubtitle: UIColor { color("mapCardSubtitle", fallback: "#B8FFFFFF") }
    static var mapCardMeta: UIColor { color("mapCardMeta", fallback: "#9EFFFFFF") }
    static var mapCardIconBackground: UIColor { color("mapCardIconBackground", fallback: "#C7000000") }
    static var mapPinBackground: UIColor { color("mapPinBackground", fallback: "#DB000000") }
    static var mapPinBorder: UIColor { color("mapPinBorder", fallback: "#24FFFFFF") }
    static var mapPinIcon: UIColor { color("mapPinIcon", fallback: "#EBFFFFFF") }
    static var mapPinShadow: UIColor { color("mapPinShadow", fallback: "#42000000") }
    static var mapTeslaBadgeBackground: UIColor { color("mapTeslaBadgeBackground", fallback: "#E0141414") }
    static var mapTeslaPinBackground: UIColor { color("mapTeslaPinBackground", fallback: "#F573E6FF") }
    static var mapTeslaPinBorder: UIColor { color("mapTeslaPinBorder", fallback: "#2EFFFFFF") }
    static var mapTeslaPinShadow: UIColor { color("mapTeslaPinShadow", fallback: "#3D000000") }

    static var modelViewerBackground: UIColor { color("modelViewerBackground", fallback: "#292929") }
    static var modelViewerControlBackground: UIColor { color("modelViewerControlBackground", fallback: "#D1141414") }
    static var modelViewerControlBorder: UIColor { color("modelViewerControlBorder", fallback: "#1FFFFFFF") }
    static var modelViewerHintBackground: UIColor { color("modelViewerHintBackground", fallback: "#B8141414") }

    static var chargingCardFill: UIColor { color("chargingCardFill", fallback: "#12FFFFFF") }
    static var chargingCardBorder: UIColor { color("chargingCardBorder", fallback: "#1AFFFFFF") }
    static var chargingTrack: UIColor { color("chargingTrack", fallback: "#14FFFFFF") }
    static var chargingGlow: UIColor { color("chargingGlow", fallback: "#4D73E6FF") }
    static var chargingStrongGlow: UIColor { color("chargingStrongGlow", fallback: "#8C73E6FF") }
    static var chargingAccentSoft: UIColor { color("chargingAccentSoft", fallback: "#2E73E6FF") }
    static var chargingBatteryCritical: UIColor { color("chargingBatteryCritical", fallback: "#FF1F1F") }
    static var chargingBatteryMid: UIColor { color("chargingBatteryMid", fallback: "#FF8CB8") }
    static var chargingBatteryGood: UIColor { color("chargingBatteryGood", fallback: "#73E6FF") }
    static var chargingButtonFill: UIColor { color("chargingButtonFill", fallback: "#F2171F2B") }
    static var chargingButtonBorder: UIColor { color("chargingButtonBorder", fallback: "#14FFFFFF") }
    static var chargingStatusBackground: UIColor { color("chargingStatusBackground", fallback: "#33338CA6") }
    static var chargingSliderTrack: UIColor { color("chargingSliderTrack", fallback: "#24FFFFFF") }
    static var chargingSliderFill: UIColor { color("chargingSliderFill", fallback: "#F273E6FF") }

    static func color(_ uiColor: UIColor) -> Color {
        Color(uiColor: uiColor)
    }

    private static func color(_ name: String, fallback: String) -> UIColor {
        ThemeProvider.shared.color(named: name, fallbackHex: fallback)
    }
}
