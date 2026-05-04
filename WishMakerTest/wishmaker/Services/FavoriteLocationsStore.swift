//
//  FavoriteLocationsStore.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.

import CoreData
import Foundation

protocol FavoriteLocationsStoreProtocol {
    func fetchFavorites() throws -> [AppLocation]
    func save(_ location: AppLocation) throws
    func remove(id: UUID) throws
}

final class FavoriteLocationsStore: FavoriteLocationsStoreProtocol {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchFavorites() throws -> [AppLocation] {
        let request = FavoriteLocationEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(FavoriteLocationEntity.title), ascending: true)]
        return try context.fetch(request).compactMap(\.appLocation)
    }

    func save(_ location: AppLocation) throws {
        let request = FavoriteLocationEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K == %@",
            #keyPath(FavoriteLocationEntity.uuid),
            location.id as CVarArg
        )
        request.fetchLimit = 1

        let object = try context.fetch(request).first
            ?? FavoriteLocationEntity(context: context)
        object.update(with: location)
        try context.save()
    }

    func remove(id: UUID) throws {
        let request = FavoriteLocationEntity.fetchRequest()
        request.predicate = NSPredicate(
            format: "%K == %@",
            #keyPath(FavoriteLocationEntity.uuid),
            id as CVarArg
        )

        let matches = try context.fetch(request)
        matches.forEach(context.delete)

        if context.hasChanges {
            try context.save()
        }
    }
}
