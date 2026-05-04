//
//  AppCopy+Strings.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Foundation

extension AppCopy {
    var appTitle: String { Localization.string("app_title", language: language) }
    var systemLanguageNotice: String {
        Localization.string("system_language_notice", language: language)
    }

    var profileTitle: String { Localization.string("profile_title", language: language) }
    var premiumDriver: String { Localization.string("premium_driver", language: language) }
    var preferences: String { Localization.string("preferences", language: language) }
    var overview: String { Localization.string("overview", language: language) }
    var quickActions: String { Localization.string("quick_actions", language: language) }
    var trips: String { Localization.string("trips", language: language) }
    var rating: String { Localization.string("rating", language: language) }
    var energy: String { Localization.string("energy", language: language) }
    var control: String { Localization.string("control", language: language) }
    var climate: String { Localization.string("climate", language: language) }
    var account: String { Localization.string("account", language: language) }
    var tripsAction: String { Localization.string("trips_action", language: language) }
    var chargeTarget: String { Localization.string("charge_target", language: language) }
    var homeCharging: String { Localization.string("home_charging", language: language) }
    var security: String { Localization.string("security", language: language) }
    var faceIdEnabled: String { Localization.string("face_id_enabled", language: language) }
    var chargingTitle: String { Localization.string("charging_title", language: language) }
    var chargeLimit: String { Localization.string("charge_limit", language: language) }
    var chargeProtection: String { Localization.string("charge_protection", language: language) }
    var untilFull: String { Localization.string("until_full", language: language) }
    var speed: String { Localization.string("speed", language: language) }
    var addedEnergy: String { Localization.string("added_energy", language: language) }
    var addedRange: String { Localization.string("added_range", language: language) }
    var cost: String { Localization.string("cost", language: language) }
    var status: String { Localization.string("status", language: language) }
    var active: String { Localization.string("active", language: language) }
    var inactive: String { Localization.string("inactive", language: language) }
    var changeChargeLimitTitle: String { Localization.string("change_charge_limit_title", language: language) }
    var changeChargeLimitMessage: String { Localization.string("change_charge_limit_message", language: language) }
    var reachedChargeLimitTitle: String { Localization.string("reached_charge_limit_title", language: language) }
    func reachedChargeLimitMessage(limit: Int) -> String {
        String(format: Localization.string("reached_charge_limit_message_format", language: language), "\(limit)")
    }

    func recommendedChargeLimit(_ limit: Int) -> String {
        String(format: Localization.string("recommended_charge_limit_format", language: language), "\(limit)")
    }

    var quickControls: String { Localization.string("quick_controls", language: language) }
    var startCharging: String { Localization.string("start_charging", language: language) }
    var stopCharging: String { Localization.string("stop_charging", language: language) }
    var stopChargingConfirmTitle: String { Localization.string("stop_charging_confirm_title", language: language) }
    var stopChargingConfirmMessage: String { Localization.string("stop_charging_confirm_message", language: language) }
    var openChargePort: String { Localization.string("open_charge_port", language: language) }
    var setChargeLimit: String { Localization.string("set_charge_limit", language: language) }
    var scheduleCharging: String { Localization.string("schedule_charging", language: language) }
    var placesTitle: String { Localization.string("places_title", language: language) }

    func placesSubtitleAuthorized(vehicle: TeslaVehicle) -> String {
        String(format: Localization.string("places_subtitle_authorized_format", language: language), vehicle.displayName)
    }

    func placesSubtitleDenied(vehicle: TeslaVehicle) -> String {
        String(format: Localization.string("places_subtitle_denied_format", language: language), vehicle.displayName)
    }

    var requestingLocation: String { Localization.string("requesting_location", language: language) }
    var all: String { Localization.string("all", language: language) }
    var favorites: String { Localization.string("favorites", language: language) }
    var noFavoritePlaces: String { Localization.string("no_favorite_places", language: language) }
    var addFavoritesHint: String { Localization.string("add_favorites_hint", language: language) }
    var favoritesTitle: String { Localization.string("favorites_title", language: language) }
    var close: String { Localization.string("close", language: language) }
    var buildRouteTitle: String { Localization.string("build_route_title", language: language) }
    var notNow: String { Localization.string("not_now", language: language) }
    var build: String { Localization.string("build", language: language) }

    func routePrompt(location: String) -> String {
        String(format: Localization.string("route_prompt_format", language: language), location)
    }

    var avatar: String { Localization.string("avatar", language: language) }
    var languageLabel: String { Localization.string("language_label", language: language) }
    var cars: String { Localization.string("cars", language: language) }
    var addCar: String { Localization.string("add_car", language: language) }
    var bindCar: String { Localization.string("bind_car", language: language) }
    var noCarsBound: String { Localization.string("no_cars_bound", language: language) }
    var chooseAvatar: String { Localization.string("choose_avatar", language: language) }
    var chooseVehicle: String { Localization.string("choose_vehicle", language: language) }
    var batteryRangeSuffix: String { Localization.string("battery_range_suffix", language: language) }

    var languageSetEnglish: String { Localization.string("language_set_english", language: language) }
    var languageSetRussian: String { Localization.string("language_set_russian", language: language) }
    var autopilot: String { Localization.string("autopilot", language: language) }
    var preferenceGeneric: String { Localization.string("preference_generic", language: language) }

    var select: String { Localization.string("select", language: language) }
    var chooseChargingStation: String { Localization.string("choose_charging_station", language: language) }

    func startChargingPrompt(station: String) -> String {
        String(format: Localization.string("start_charging_prompt_format", language: language), station)
    }

    var start: String { Localization.string("start", language: language) }
    var stop: String { Localization.string("stop", language: language) }
    var ok: String { Localization.string("ok", language: language) }
    var viewAngleLeft: String { Localization.string("view_angle_left", language: language) }
    var viewAngleFront: String { Localization.string("view_angle_front", language: language) }
    var viewAngleRight: String { Localization.string("view_angle_right", language: language) }
    var viewAngleRear: String { Localization.string("view_angle_rear", language: language) }
}
