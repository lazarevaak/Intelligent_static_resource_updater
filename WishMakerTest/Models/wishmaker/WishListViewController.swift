import UIKit
import CoreData

class WishListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private var wishes: [Event] = []
    private let tableView = UITableView()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
        fetchWishes()
    }

    private func configureUI() {
        tableView.frame = view.bounds
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
    }

    private func fetchWishes() {
        let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
        let request: NSFetchRequest<Event> = Event.fetchRequest()
        
        do {
            wishes = try context.fetch(request)
            tableView.reloadData()
        } catch {
            print("Failed to fetch wishes: \(error.localizedDescription)")
        }
    }

    // MARK: - UITableViewDataSource методы

    // Количество строк в таблице
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return wishes.count
    }

    // Настройка ячеек таблицы
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WishCell") ?? UITableViewCell(style: .default, reuseIdentifier: "WishCell")
        
        let wish = wishes[indexPath.row]
        cell.textLabel?.text = wish.title // Отображаем название желания
        return cell
    }

    // MARK: - UITableViewDelegate метод

    // Обработка выбора строки
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedWish = wishes[indexPath.row]
        // Логика обработки выбранного желания (например, передача данных для планирования события)
    }
}
