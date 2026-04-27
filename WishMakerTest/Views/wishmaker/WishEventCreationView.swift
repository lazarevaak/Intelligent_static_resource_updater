import UIKit
import CoreData

class WishEventCreationView: UIViewController {
    
    var backgroundColor: UIColor?

    private let titleField = UITextField()
    private let descriptionField = UITextField()
    private let startDateField = UITextField()
    private let endDateField = UITextField()
    private let saveButton = UIButton(type: .system)

    let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = backgroundColor ?? .white
        configureUI()
    }

    private func configureUI() {
        titleField.placeholder = "Event Title"
        titleField.borderStyle = .roundedRect
        titleField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleField)
        
        descriptionField.placeholder = "Event Description"
        descriptionField.borderStyle = .roundedRect
        descriptionField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descriptionField)
        
        startDateField.placeholder = "Start Date"
        startDateField.borderStyle = .roundedRect
        startDateField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startDateField)
        
        endDateField.placeholder = "End Date"
        endDateField.borderStyle = .roundedRect
        endDateField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(endDateField)
        
        saveButton.setTitle("Save Event", for: .normal)
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.addTarget(self, action: #selector(saveEvent), for: .touchUpInside)
        view.addSubview(saveButton)

        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: view.topAnchor, constant: 50),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            descriptionField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 20),
            descriptionField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descriptionField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            startDateField.topAnchor.constraint(equalTo: descriptionField.bottomAnchor, constant: 20),
            startDateField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            startDateField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            endDateField.topAnchor.constraint(equalTo: startDateField.bottomAnchor, constant: 20),
            endDateField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            endDateField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            saveButton.topAnchor.constraint(equalTo: endDateField.bottomAnchor, constant: 30),
            saveButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    @objc private func saveEvent() {
        guard let title = titleField.text, !title.isEmpty,
              let description = descriptionField.text, !description.isEmpty,
              let startDate = startDateField.text, !startDate.isEmpty,
              let endDate = endDateField.text, !endDate.isEmpty else {
            showAlert(message: "Please fill in all fields.")
            return
        }
        
        let newEvent = Event(context: context)
        newEvent.title = title
        newEvent.eventDescription = description
        newEvent.startDate = startDate
        newEvent.endDate = endDate
        
        do {
            try context.save()
            showAlert(message: "Event saved successfully!")
        } catch {
            showAlert(message: "Error saving event.")
        }
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: "Notification", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
