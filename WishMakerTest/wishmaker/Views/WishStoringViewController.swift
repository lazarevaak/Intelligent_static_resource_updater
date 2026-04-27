import UIKit

final class WishStoringViewController: UIViewController {
    
    // MARK: - Properties
    private let tableView = UITableView()
    private var wishArray: [String] = []
    private let defaults = UserDefaults.standard
    private let wishKey = "wishes"
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        configureTableView()
        loadWishes()
    }
    
    // MARK: - Data Loading
    private func loadWishes() {
        wishArray = defaults.array(forKey: wishKey) as? [String] ?? []
        tableView.reloadData()
    }
    
    // MARK: - Data Saving
    private func saveWishes() {
        defaults.set(wishArray, forKey: wishKey)
    }
    
    // MARK: - UI Configuration
    private func configureTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(AddWishCell.self, forCellReuseIdentifier: AddWishCell.reuseId)
        tableView.register(WrittenWishCell.self, forCellReuseIdentifier: WrittenWishCell.reuseId)
        view.addSubview(tableView)
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

// MARK: - UITableViewDataSource
extension WishStoringViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 1 : wishArray.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: AddWishCell.reuseId, for: indexPath) as? AddWishCell else {
                return UITableViewCell()
            }
            cell.addWish = { [weak self] wish in
                self?.wishArray.append(wish)
                self?.saveWishes()
                tableView.reloadData()
            }
            return cell
        } else {
            guard let cell = tableView.dequeueReusableCell(withIdentifier: WrittenWishCell.reuseId, for: indexPath) as? WrittenWishCell else {
                return UITableViewCell()
            }
            cell.configure(with: wishArray[indexPath.row])
            return cell
        }
    }
}

// MARK: - UITableViewDelegate
extension WishStoringViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1 else { return nil }
        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.wishArray.remove(at: indexPath.row)
            self?.saveWishes()
            tableView.deleteRows(at: [indexPath], with: .automatic)
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }
}

