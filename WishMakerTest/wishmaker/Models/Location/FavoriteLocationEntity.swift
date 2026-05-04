//
//  FavoriteLocationEntity.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 28.04.2026.

import CoreData
import Foundation

@objc(FavoriteLocationEntity)
final class FavoriteLocationEntity: NSManagedObject {
    static let entityName = "FavoriteLocation"

    @NSManaged var uuid: UUID?
    @NSManaged var title: String?
    @NSManaged var subtitle: String?
    @NSManaged var typeRawValue: String?
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var address: String?
    @NSManaged var workingHours: String?
    @NSManaged var distanceKm: NSNumber?
    @NSManaged var superchargerPowerKw: NSNumber?
    @NSManaged var superchargerPricePerKwh: NSNumber?
}

extension FavoriteLocationEntity {
    @nonobjc
    class func fetchRequest() -> NSFetchRequest<FavoriteLocationEntity> {
        NSFetchRequest<FavoriteLocationEntity>(entityName: entityName)
    }

    var appLocation: AppLocation? {
        guard
            let id = uuid,
            let title,
            let subtitle,
            let typeRawValue,
            let type = LocationType(rawValue: typeRawValue),
            let address
        else {
            return nil
        }

        return AppLocation(
            id: id,
            title: title,
            subtitle: subtitle,
            type: type,
            latitude: latitude,
            longitude: longitude,
            address: address,
            workingHours: workingHours,
            distanceKm: distanceKm?.doubleValue,
            supercharger: type == .supercharger
                ? SuperchargerDetails(
                    powerKw: superchargerPowerKw?.doubleValue ?? 72,
                    pricePerKwh: superchargerPricePerKwh?.doubleValue ?? 0.35
                )
                : nil
        )
    }

    func update(with location: AppLocation) {
        uuid = location.id
        title = location.title
        subtitle = location.subtitle
        typeRawValue = location.type.rawValue
        latitude = location.latitude
        longitude = location.longitude
        address = location.address
        workingHours = location.workingHours
        distanceKm = location.distanceKm.map(NSNumber.init(value:))
        superchargerPowerKw = (location.superchargerDetails?.powerKw).map(NSNumber.init(value:))
        superchargerPricePerKwh = (location.superchargerDetails?.pricePerKwh).map(NSNumber.init(value:))
    }
}
