import Foundation
import CoreData

extension Event {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Event> {
        return NSFetchRequest<Event>(entityName: "Event")
    }

    @NSManaged public var title: String?
    @NSManaged public var eventDescription: String?
    @NSManaged public var startDate: String?
    @NSManaged public var endDate: String?

}

