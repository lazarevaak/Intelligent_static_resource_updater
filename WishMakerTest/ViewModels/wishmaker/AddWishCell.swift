import UIKit

final class AddWishCell: UITableViewCell {
    
    // MARK: - Properties
    static let reuseId = "AddWishCell"
    
    var addWish: ((String) -> Void)?
    var updateWish: ((String) -> Void)? // Callback for updating a wish
    var removeWish: (() -> Void)? // Callback for removing a wish
    private var isEditingWish = false // Edit mode flag

    // MARK: - UI Elements
    private let textView: UITextView = {
        let view = UITextView()
        view.font = UIFont.systemFont(ofSize: 16)
        view.layer.borderColor = UIColor.gray.cgColor
        view.layer.borderWidth = 1
        view.layer.cornerRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        view.text = "Введите желание..."
        view.textColor = .lightGray
        view.isEditable = true
        return view
    }()
    
    private let addButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Добавить", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isEnabled = false
        return button
    }()
    
    // MARK: - Initializers
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        configureUI()
        addButton.addTarget(self, action: #selector(addOrUpdateButtonPressed), for: .touchUpInside)
        textView.delegate = self
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Configuration
    private func configureUI() {
        selectionStyle = .none
        contentView.addSubview(textView)
        contentView.addSubview(addButton)
        
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textView.heightAnchor.constraint(equalToConstant: 60),
            
            addButton.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            addButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }
    
    // MARK: - Configuration Methods
    func configureForEditing(with text: String) {
        textView.text = text
        textView.textColor = .black
        isEditingWish = true
        addButton.setTitle("Сохранить", for: .normal)
        addButton.isEnabled = true
    }
    
    @objc private func addOrUpdateButtonPressed() {
        guard let text = textView.text?.trimmingCharacters(in: .whitespaces), !text.isEmpty, text != "Введите желание..." else { return }
        
        if isEditingWish {
            updateWish?(text)
            isEditingWish = false
            addButton.setTitle("Добавить", for: .normal)
        } else {
            addWish?(text)
        }
        
        resetTextView()
    }
    
    func removeCurrentWish() {
        resetTextView()
        removeWish?()
    }
    
    private func resetTextView() {
        textView.text = "Введите желание..."
        textView.textColor = .lightGray
        addButton.setTitle("Добавить", for: .normal)
        addButton.isEnabled = false
        textView.resignFirstResponder()
    }
}

// MARK: - UITextViewDelegate
extension AddWishCell: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        if textView.text == "Введите желание..." {
            textView.text = ""
            textView.textColor = .black
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textView.text.isEmpty {
            resetTextView()
        }
    }
    
    func textViewDidChange(_ textView: UITextView) {
        addButton.isEnabled = !textView.text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

