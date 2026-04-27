import EventKit

// MARK: - CalendarManaging Protocol
protocol CalendarManaging {
    func create(eventModel: CalendarEventModel) -> Bool
}

// MARK: - CalendarEventModel
struct CalendarEventModel {
    var title: String
    var startDate: Date
    var endDate: Date
    var note: String?
}

// MARK: - CalendarManager Implementation
final class CalendarManager: CalendarManaging {

    private let eventStore: EKEventStore = EKEventStore()

    // MARK: - Основной метод для создания события
    func create(eventModel: CalendarEventModel) -> Bool {
        var result: Bool = false
        let group = DispatchGroup()

        group.enter()
        create(eventModel: eventModel) { isCreated in
            result = isCreated
            group.leave()
        }

        group.wait() // Ждем завершения операции
        return result
    }

    // MARK: - Метод для создания события с использованием замыкания
    func create(eventModel: CalendarEventModel, completion: ((Bool) -> Void)?) {

        // Запрашиваем доступ к календарю
        let createEvent: EKEventStoreRequestAccessCompletionHandler = { [weak self] (granted, error) in
            guard granted, error == nil, let self = self else {
                completion?(false)
                return
            }

            // Создаем объект события
            let event = EKEvent(eventStore: self.eventStore)
            event.title = eventModel.title
            event.startDate = eventModel.startDate
            event.endDate = eventModel.endDate
            event.notes = eventModel.note
            event.calendar = self.eventStore.defaultCalendarForNewEvents

            // Сохраняем событие в календаре
            do {
                try self.eventStore.save(event, span: .thisEvent)
                completion?(true)
            } catch let error as NSError {
                print("Failed to save event with error: \(error.localizedDescription)")
                completion?(false)
            }
        }

        // Для iOS 17 и выше используем requestFullAccessToEvents
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents(completion: createEvent)
        } else {
            eventStore.requestAccess(to: .event, completion: createEvent)
        }
    }
}
