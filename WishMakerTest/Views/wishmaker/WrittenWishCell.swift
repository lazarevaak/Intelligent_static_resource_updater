import UIKit

final class WrittenWishCell: UITableViewCell {
    // MARK: - Reuse Identifier
    static let reuseId = "WrittenWishCell"
    
    // MARK: - Constants
    private enum Constants {
        static let fontSize: CGFloat = 16
        static let leadingPadding: CGFloat = 16
        static let trailingPadding: CGFloat = 16
        static let topPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 8
    }
    
    // MARK: - UI Elements
    private let wishLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: Constants.fontSize)
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()
    
    // MARK: - Initializers
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureUI()
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Configuration
    func configure(with wish: String) {
        wishLabel.text = wish
    }
    
    // MARK: - UI Setup
    private func configureUI() {
        selectionStyle = .none
        addSubview(wishLabel)
        
        NSLayoutConstraint.activate([
            wishLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.leadingPadding),
            wishLabel.topAnchor.constraint(equalTo: topAnchor, constant: Constants.topPadding),
            wishLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.trailingPadding),
            wishLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.bottomPadding)
        ])
    }
}
