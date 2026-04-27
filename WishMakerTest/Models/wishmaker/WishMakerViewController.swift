import UIKit
import CoreData

final class WishMakerViewController: UIViewController {

    // MARK: - Константы
    private enum Constants {
        static let sliderMin: Double = 0
        static let sliderMaxRed: Double = 1
        static let sliderMaxRGB: Double = 255
        static let titleFontSize: CGFloat = 32
        static let descriptionFontSize: CGFloat = 16
        static let stackRadius: CGFloat = 20
        static let stackBottom: CGFloat = -40
        static let stackLeading: CGFloat = 20
        static let descriptionTopOffset: CGFloat = 20
        static let titleText = "WishMaker"
        static let descriptionText = "Make your wishes come true!"
        static let titleColor = UIColor(red: 255/255, green: 215/255, blue: 0/255, alpha: 1.0)
        static let buttonText = "Add Wish"
        static let buttonHeight: CGFloat = 50
        static let buttonBottom: CGFloat = -20
        static let spacing: CGFloat = 10
    }

    // MARK: - Свойства
    private let titleView = UILabel()
    private let descriptionView = UILabel()
    private let addMoreWishesButton: UIButton = UIButton(type: .system)
    private let scheduleWishesButton: UIButton = UIButton(type: .system)
    private let actionStack = UIStackView()
    private let addEventButton = UIButton(type: .system)

    private var redValue: CGFloat = 0
    private var greenValue: CGFloat = 0
    private var blueValue: CGFloat = 0

    private var currentColor: UIColor = .systemPink {
        didSet {
            view.backgroundColor = currentColor
            addMoreWishesButton.setTitleColor(currentColor, for: .normal)
            scheduleWishesButton.setTitleColor(currentColor, for: .normal)
        }
    }

    // MARK: - Жизненный цикл
    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    // MARK: - Настройка UI
    private func configureUI() {
        view.backgroundColor = currentColor
        configureTitle()
        configureDescription()
        configureActionStack()
        configureSliders()
        configureAddEventButton()
    }

    private func configureTitle() {
        titleView.translatesAutoresizingMaskIntoConstraints = false
        titleView.text = Constants.titleText
        titleView.font = UIFont.boldSystemFont(ofSize: Constants.titleFontSize)
        titleView.textColor = Constants.titleColor

        view.addSubview(titleView)
        NSLayoutConstraint.activate([
            titleView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20)
        ])
    }

    private func configureDescription() {
        descriptionView.translatesAutoresizingMaskIntoConstraints = false
        descriptionView.text = Constants.descriptionText
        descriptionView.font = UIFont.systemFont(ofSize: Constants.descriptionFontSize)
        descriptionView.textColor = .white
        descriptionView.numberOfLines = 0
        descriptionView.textAlignment = .center

        view.addSubview(descriptionView)
        NSLayoutConstraint.activate([
            descriptionView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            descriptionView.topAnchor.constraint(equalTo: titleView.bottomAnchor, constant: Constants.descriptionTopOffset),
            descriptionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.stackLeading)
        ])
    }

    private func configureActionStack() {
        actionStack.axis = .vertical
        view.addSubview(actionStack)
        actionStack.spacing = Constants.spacing

        for button in [addMoreWishesButton, scheduleWishesButton] {
            actionStack.addArrangedSubview(button)
        }

        configureAddMoreWishes()
        configureScheduleWishes()

        actionStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            actionStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            actionStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.stackLeading),
            actionStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: Constants.stackBottom)
        ])
    }

    private func configureAddMoreWishes() {
        addMoreWishesButton.setTitle("Add More Wishes", for: .normal)
        addMoreWishesButton.setTitleColor(currentColor, for: .normal)
        addMoreWishesButton.backgroundColor = .white
        addMoreWishesButton.layer.cornerRadius = 10
        addMoreWishesButton.addTarget(self, action: #selector(addWishButtonPressed), for: .touchUpInside)
    }

    private func configureScheduleWishes() {
        scheduleWishesButton.setTitle("Schedule wish granting", for: .normal)
        scheduleWishesButton.setTitleColor(currentColor, for: .normal)
        scheduleWishesButton.backgroundColor = .white
        scheduleWishesButton.layer.cornerRadius = 10
        scheduleWishesButton.addTarget(self, action: #selector(scheduleWishesButtonPressed), for: .touchUpInside)
    }

    private func configureSliders() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.layer.cornerRadius = Constants.stackRadius
        stack.clipsToBounds = true
        view.addSubview(stack)

        let sliderRed = CustomSlider(title: "Red", min: Constants.sliderMin, max: Constants.sliderMaxRed)
        let sliderBlue = CustomSlider(title: "Blue", min: Constants.sliderMin, max: Constants.sliderMaxRGB)
        let sliderGreen = CustomSlider(title: "Green", min: Constants.sliderMin, max: Constants.sliderMaxRGB)

        for slider in [sliderRed, sliderBlue, sliderGreen] {
            stack.addArrangedSubview(slider)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.stackLeading),
            stack.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: Constants.stackBottom)
        ])

        sliderRed.valueChanged = { [weak self] (value: Double) in
            self?.redValue = CGFloat(value)
            self?.updateBackgroundColor()
        }

        sliderGreen.valueChanged = { [weak self] (value: Double) in
            self?.greenValue = CGFloat(value) / 255.0
            self?.updateBackgroundColor()
        }

        sliderBlue.valueChanged = { [weak self] (value: Double) in
            self?.blueValue = CGFloat(value) / 255.0
            self?.updateBackgroundColor()
        }
    }

    private func updateBackgroundColor() {
        currentColor = UIColor(red: redValue, green: greenValue, blue: blueValue, alpha: 1.0)
    }

    private func configureAddEventButton() {
        addEventButton.setTitle("+", for: .normal)
        addEventButton.titleLabel?.font = UIFont.systemFont(ofSize: 40, weight: .bold)
        addEventButton.translatesAutoresizingMaskIntoConstraints = false
        addEventButton.addTarget(self, action: #selector(presentEventCreation), for: .touchUpInside)

        view.addSubview(addEventButton)

        NSLayoutConstraint.activate([
            addEventButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            addEventButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }

    @objc private func addWishButtonPressed() {
        let wishStoringVC = WishStoringViewController()
        present(wishStoringVC, animated: true)
    }

    @objc private func scheduleWishesButtonPressed() {
        let vc = WishCalendarViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func presentEventCreation() {
        let eventCreationVC = WishEventCreationView()
        let navigationController = UINavigationController(rootViewController: eventCreationVC)
        present(navigationController, animated: true)
    }
}

