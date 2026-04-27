import UIKit

// MARK: - WishEventCell
final class WishEventCell: UICollectionViewCell {

    // MARK: - Статические свойства
    static let reuseIdentifier: String = "WishEventCell"
    
    // MARK: - Элементы UI
    private let wrapView: UIView = UIView()
    private let titleLabel: UILabel = UILabel()
    private let descriptionLabel: UILabel = UILabel()
    private let startDateLabel: UILabel = UILabel()
    private let endDateLabel: UILabel = UILabel()

    // MARK: - Константы (например, для отступов, шрифтов)
    private enum Constants {
        static let offset: CGFloat = 10
        static let cornerRadius: CGFloat = 12
        static let backgroundColor: UIColor = .white
        static let titleFont: UIFont = UIFont.boldSystemFont(ofSize: 16)
        static let descriptionFont: UIFont = UIFont.systemFont(ofSize: 14)
        static let titleTop: CGFloat = 10
        static let titleLeading: CGFloat = 10
        static let descriptionTop: CGFloat = 5
        static let descriptionLeading: CGFloat = 10
        static let startDateTop: CGFloat = 5
        static let endDateTop: CGFloat = 5
    }

    // MARK: - Инициализация
    override init(frame: CGRect) {
        super.init(frame: frame)
        configureWrap()
        configureTitleLabel()
        configureDescriptionLabel()
        configureStartDateLabel()
        configureEndDateLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Конфигурация UI
    private func configureWrap() {
        addSubview(wrapView)
        wrapView.translatesAutoresizingMaskIntoConstraints = false
        wrapView.layer.cornerRadius = Constants.cornerRadius
        wrapView.backgroundColor = Constants.backgroundColor
        
        NSLayoutConstraint.activate([
            wrapView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.offset),
            wrapView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.offset),
            wrapView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.offset),
            wrapView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.offset)
        ])
    }

    private func configureTitleLabel() {
        wrapView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = Constants.titleFont
        titleLabel.textColor = .black
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: wrapView.topAnchor, constant: Constants.titleTop),
            titleLabel.leadingAnchor.constraint(equalTo: wrapView.leadingAnchor, constant: Constants.titleLeading)
        ])
    }

    private func configureDescriptionLabel() {
        wrapView.addSubview(descriptionLabel)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = Constants.descriptionFont
        descriptionLabel.textColor = .gray
        descriptionLabel.numberOfLines = 0
        
        NSLayoutConstraint.activate([
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Constants.descriptionTop),
            descriptionLabel.leadingAnchor.constraint(equalTo: wrapView.leadingAnchor, constant: Constants.descriptionLeading),
            descriptionLabel.trailingAnchor.constraint(equalTo: wrapView.trailingAnchor, constant: -Constants.descriptionLeading)
        ])
    }

    private func configureStartDateLabel() {
        wrapView.addSubview(startDateLabel)
        startDateLabel.translatesAutoresizingMaskIntoConstraints = false
        startDateLabel.font = UIFont.systemFont(ofSize: 12)
        startDateLabel.textColor = .darkGray
        
        NSLayoutConstraint.activate([
            startDateLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: Constants.startDateTop),
            startDateLabel.leadingAnchor.constraint(equalTo: wrapView.leadingAnchor, constant: Constants.descriptionLeading)
        ])
    }

    private func configureEndDateLabel() {
        wrapView.addSubview(endDateLabel)
        endDateLabel.translatesAutoresizingMaskIntoConstraints = false
        endDateLabel.font = UIFont.systemFont(ofSize: 12)
        endDateLabel.textColor = .darkGray
        
        NSLayoutConstraint.activate([
            endDateLabel.topAnchor.constraint(equalTo: startDateLabel.bottomAnchor, constant: Constants.endDateTop),
            endDateLabel.leadingAnchor.constraint(equalTo: wrapView.leadingAnchor, constant: Constants.descriptionLeading)
        ])
    }

    // MARK: - Конфигурация данных для ячейки
    func configure(with event: WishEventModel) {
        titleLabel.text = event.title
        descriptionLabel.text = event.description
        startDateLabel.text = "Start Date: \(event.startDate)"
        endDateLabel.text = "End Date: \(event.endDate)"
    }
}

// MARK: - Модель для события
struct WishEventModel {
    let title: String
    let description: String
    let startDate: String
    let endDate: String
}
