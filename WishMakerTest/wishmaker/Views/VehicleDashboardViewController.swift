//
//  VehicleDashboardViewController.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import SceneKit
import SwiftUI
import UIKit

final class VehicleDashboardViewController: UIViewController {
    private enum ViewAnglePreset: Int, CaseIterable {
        case left
        case front
        case right
        case rear

        var yaw: Float {
            switch self {
            case .left:
                return Float.pi / 2
            case .front:
                return 0
            case .right:
                return -Float.pi / 2
            case .rear:
                return Float.pi
            }
        }

        var systemImageName: String {
            switch self {
            case .left:
                return "arrow.left"
            case .front:
                return "arrow.up"
            case .right:
                return "arrow.right"
            case .rear:
                return "arrow.down"
            }
        }

        func accessibilityTitle(copy: AppCopy) -> String {
            switch self {
            case .left:
                return copy.viewAngleLeft
            case .front:
                return copy.viewAngleFront
            case .right:
                return copy.viewAngleRight
            case .rear:
                return copy.viewAngleRear
            }
        }
    }

    private let viewModel: VehicleDashboardViewModel
    private let profileViewControllerFactory: () -> UIViewController
    private let gradientView = GradientBackgroundView()

    private let dashboardCard = UIView()
    private let titleLabel = UILabel()
    private let rangeLabel = UILabel()
    private let profileButton = UIButton(type: .system)
    private let sceneView = SCNView()
    private let quickActionsBar = UIStackView()
    private let angleButtons: [UIButton] = ViewAnglePreset.allCases.map { _ in UIButton(type: .system) }
    private var selectedAnglePreset: ViewAnglePreset = .front
    private var modelWrapperNode: SCNNode?

    init(
        viewModel: VehicleDashboardViewModel,
        profileViewControllerFactory: @escaping () -> UIViewController
    ) {
        self.viewModel = viewModel
        self.profileViewControllerFactory = profileViewControllerFactory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureGradient()
        configureLayout()
        configureDashboardCard()
        setupBindings()
        configureModelView()
        viewModel.load()
    }

    private func configureGradient() {
        view.backgroundColor = AppColors.appBackground
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gradientView)

        NSLayoutConstraint.activate([
            gradientView.topAnchor.constraint(equalTo: view.topAnchor),
            gradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureLayout() {
        dashboardCard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dashboardCard)

        NSLayoutConstraint.activate([
            dashboardCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            dashboardCard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dashboardCard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dashboardCard.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func configureDashboardCard() {
        dashboardCard.subviews.forEach { $0.removeFromSuperview() }
        quickActionsBar.arrangedSubviews.forEach { subview in
            quickActionsBar.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        dashboardCard.backgroundColor = .clear
        dashboardCard.layer.cornerRadius = 0
        dashboardCard.layer.borderWidth = 0

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 37, weight: .bold)
        titleLabel.textColor = AppColors.primaryText

        rangeLabel.translatesAutoresizingMaskIntoConstraints = false

        profileButton.translatesAutoresizingMaskIntoConstraints = false
        profileButton.setImage(UIImage(systemName: "person.fill"), for: .normal)
        profileButton.tintColor = AppColors.hintText
        profileButton.backgroundColor = AppColors.controlBackground
        profileButton.layer.cornerRadius = 28
        profileButton.layer.borderWidth = 1
        profileButton.layer.borderColor = AppColors.elevatedBorder.cgColor
        profileButton.layer.shadowColor = AppColors.primaryText.cgColor
        profileButton.layer.shadowOpacity = 0.12
        profileButton.layer.shadowRadius = 22
        profileButton.layer.shadowOffset = CGSize(width: 0, height: 8)
        profileButton.addTarget(self, action: #selector(didTapProfileButton), for: .touchUpInside)

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.backgroundColor = .clear
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapModel))
        sceneView.addGestureRecognizer(tapGesture)

        quickActionsBar.translatesAutoresizingMaskIntoConstraints = false
        quickActionsBar.axis = .horizontal
        quickActionsBar.distribution = .fillEqually
        quickActionsBar.alignment = .fill
        quickActionsBar.spacing = 0
        quickActionsBar.backgroundColor = AppColors.quickActionsBackground
        quickActionsBar.layer.cornerRadius = 28
        quickActionsBar.isLayoutMarginsRelativeArrangement = true
        quickActionsBar.layoutMargins = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        configureAngleButtons()

        dashboardCard.addSubview(titleLabel)
        dashboardCard.addSubview(rangeLabel)
        dashboardCard.addSubview(profileButton)
        dashboardCard.addSubview(sceneView)
        dashboardCard.addSubview(quickActionsBar)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: dashboardCard.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: dashboardCard.leadingAnchor, constant: 24),

            rangeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            rangeLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            profileButton.topAnchor.constraint(equalTo: dashboardCard.topAnchor, constant: 22),
            profileButton.trailingAnchor.constraint(equalTo: dashboardCard.trailingAnchor, constant: -22),
            profileButton.widthAnchor.constraint(equalToConstant: 56),
            profileButton.heightAnchor.constraint(equalToConstant: 56),

            sceneView.topAnchor.constraint(equalTo: rangeLabel.bottomAnchor, constant: 14),
            sceneView.leadingAnchor.constraint(equalTo: dashboardCard.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: dashboardCard.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: quickActionsBar.topAnchor, constant: -12),

            quickActionsBar.leadingAnchor.constraint(equalTo: dashboardCard.leadingAnchor, constant: 22),
            quickActionsBar.trailingAnchor.constraint(equalTo: dashboardCard.trailingAnchor, constant: -22),
            quickActionsBar.bottomAnchor.constraint(equalTo: dashboardCard.bottomAnchor, constant: -20),
            quickActionsBar.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    private func configureModelView() {
        guard let vehicle = viewModel.vehicle else {
            sceneView.scene = nil
            return
        }

        configureScene(
            sceneView,
            modelAssetPath: vehicle.modelAssetPath,
            cameraPosition: SCNVector3(x: 0, y: 0.7, z: 8.4),
            modelEulerAngles: SCNVector3(x: 0, y: -.pi / 4.8, z: 0),
            modelScale: SCNVector3(x: 1, y: 1, z: 1),
            modelPosition: SCNVector3(x: 0, y: 0, z: 0),
            lightIntensity: 1300,
            ambientIntensity: 520,
            fitSize: SCNVector3(x: 8.8, y: 3.6, z: 5.6)
        )
    }

    private func setupBindings() {
        viewModel.onUpdate = { [weak self] in
            self?.refreshVehicleContent()
        }
    }

    private func refreshVehicleContent() {
        guard let vehicle = viewModel.vehicle else { return }

        titleLabel.text = vehicle.brandTitle
        rangeLabel.attributedText = NSAttributedString(string: vehicle.displayName, attributes: [
            .foregroundColor: AppColors.rangeText,
            .font: UIFont.systemFont(ofSize: 20, weight: .medium)
        ])

        configureModelView()
    }

    private func configureAngleButtons() {
        guard quickActionsBar.arrangedSubviews.isEmpty else { return }

        for preset in ViewAnglePreset.allCases {
            let button = angleButtons[preset.rawValue]
            button.translatesAutoresizingMaskIntoConstraints = false
            button.accessibilityLabel = preset.accessibilityTitle(copy: viewModel.copy)
            button.tintColor = AppColors.inactiveTint
            button.addTarget(self, action: #selector(didTapAngleButton(_:)), for: .touchUpInside)
            quickActionsBar.addArrangedSubview(button)
        }

        updateAngleButtonSelection()
    }

    private func updateAngleButtonSelection() {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)

        for preset in ViewAnglePreset.allCases {
            let button = angleButtons[preset.rawValue]
            let tintColor = preset == selectedAnglePreset ? AppColors.accentStrong : AppColors.inactiveTint
            button.setImage(
                UIImage(systemName: preset.systemImageName, withConfiguration: config)?
                    .withTintColor(tintColor, renderingMode: .alwaysOriginal),
                for: .normal
            )
        }
    }

    @objc
    private func didTapAngleButton(_ sender: UIButton) {
        guard let index = angleButtons.firstIndex(of: sender),
              let preset = ViewAnglePreset(rawValue: index) else {
            return
        }

        selectedAnglePreset = preset
        updateAngleButtonSelection()
        applyAnglePreset(preset)
    }

    private func applyAnglePreset(_ preset: ViewAnglePreset) {
        guard let modelWrapperNode else { return }

        let target = SCNVector3(x: modelWrapperNode.eulerAngles.x, y: preset.yaw, z: modelWrapperNode.eulerAngles.z)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        modelWrapperNode.eulerAngles = target
        SCNTransaction.commit()
    }

    private func configureScene(
        _ targetView: SCNView,
        modelAssetPath: String,
        cameraPosition: SCNVector3,
        modelEulerAngles: SCNVector3,
        modelScale: SCNVector3,
        modelPosition: SCNVector3,
        lightIntensity: CGFloat,
        ambientIntensity: CGFloat,
        fitSize: SCNVector3
    ) {
        let scene = SCNScene()
        targetView.scene = scene
        targetView.autoenablesDefaultLighting = true
        targetView.allowsCameraControl = false
        targetView.defaultCameraController.interactionMode = .orbitTurntable
        targetView.defaultCameraController.inertiaEnabled = true

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = cameraPosition
        scene.rootNode.addChildNode(cameraNode)
        targetView.pointOfView = cameraNode

        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = lightIntensity
        lightNode.position = SCNVector3(x: 0, y: 8, z: 8)
        scene.rootNode.addChildNode(lightNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = ambientIntensity
        scene.rootNode.addChildNode(ambientNode)

        if let assetURL = AppResourceProvider.shared.url(for: modelAssetPath),
           let modelScene = try? SCNScene(url: assetURL, options: nil) {
            let wrapperNode = SCNNode()
            modelScene.rootNode.childNodes.forEach { wrapperNode.addChildNode($0) }
            wrapperNode.eulerAngles = modelEulerAngles
            wrapperNode.scale = modelScale
            wrapperNode.position = modelPosition
            normalize(wrapperNode, fitSize: fitSize)
            scene.rootNode.addChildNode(wrapperNode)

            if targetView === sceneView {
                modelWrapperNode = wrapperNode
                applyAnglePreset(selectedAnglePreset)
            }
        }
    }

    private func normalize(_ node: SCNNode, fitSize: SCNVector3) {
        let (minBounds, maxBounds) = node.boundingBox
        let size = SCNVector3(
            x: maxBounds.x - minBounds.x,
            y: maxBounds.y - minBounds.y,
            z: maxBounds.z - minBounds.z
        )

        guard size.x > 0, size.y > 0, size.z > 0 else { return }

        let scaleX = fitSize.x / size.x
        let scaleY = fitSize.y / size.y
        let scaleZ = fitSize.z / size.z
        let scale = min(scaleX, min(scaleY, scaleZ))

        node.scale = SCNVector3(scale, scale, scale)

        let scaledMin = SCNVector3(minBounds.x * scale, minBounds.y * scale, minBounds.z * scale)
        let scaledMax = SCNVector3(maxBounds.x * scale, maxBounds.y * scale, maxBounds.z * scale)

        let centerX = (scaledMin.x + scaledMax.x) / 2
        let centerY = (scaledMin.y + scaledMax.y) / 2
        let centerZ = (scaledMin.z + scaledMax.z) / 2

        node.position = SCNVector3(-centerX, -centerY * 0.9, -centerZ)
    }

    @objc
    private func didTapProfileButton() {
        let controller = profileViewControllerFactory()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    @objc
    private func didTapModel() {
        guard let vehicle = viewModel.vehicle else { return }
        let controller = TeslaModelViewerViewController(vehicle: vehicle)
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }

    private func styleCard(_ view: UIView, cornerRadius: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.cardBackground
        view.layer.cornerRadius = cornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColors.cardBorder.cgColor
    }

    private func makeInfoRow(systemName: String, title: String, subtitle: String?) -> UIView {
        let row = UIView()

        let iconView = UIImageView(image: UIImage(systemName: systemName))
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = AppColors.iconTint
        iconView.contentMode = .scaleAspectFit

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.textColor = AppColors.secondaryText
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = AppColors.subtitleText
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .medium)

        let labels = UIStackView(arrangedSubviews: subtitle == nil ? [titleLabel] : [titleLabel, subtitleLabel])
        labels.translatesAutoresizingMaskIntoConstraints = false
        labels.axis = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let chevronView = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.tintColor = AppColors.chevronTint

        row.addSubview(iconView)
        row.addSubview(labels)
        row.addSubview(chevronView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),

            labels.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            labels.topAnchor.constraint(equalTo: row.topAnchor),
            labels.bottomAnchor.constraint(equalTo: row.bottomAnchor),

            chevronView.leadingAnchor.constraint(greaterThanOrEqualTo: labels.trailingAnchor, constant: 12),
            chevronView.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            chevronView.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        return row
    }
}
