//
//  TeslaModelViewerViewController.swift
//  wishmaker
//
//  Created by Alexandra Lazareva on 27.04.2026.
import Combine
import SceneKit
import UIKit

private final class InsetLabel: UILabel {
    var contentInsets: UIEdgeInsets = .zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }
}

final class TeslaModelViewerViewController: UIViewController {
    private enum Layout {
        static let cameraDistance: Float = 8.2
        static let pitchLimit: Float = 1.05
        static let angleStep: Float = .pi / 10
        static let buttonSize: CGFloat = 52
        static let hintHeight: CGFloat = 40
    }

    private let sceneView = SCNView()
    private let closeButton = UIButton(type: .system)
    private let upButton = UIButton(type: .system)
    private let downButton = UIButton(type: .system)
    private let leftButton = UIButton(type: .system)
    private let rightButton = UIButton(type: .system)
    private let hintLabel = InsetLabel()
    private let vehicle: TeslaVehicle
    private var themeCancellable: AnyCancellable?

    private let cameraNode = SCNNode()
    private let modelRootNode = SCNNode()

    private var yaw: Float = VehicleModelOrientation.frontYaw
    private var pitch: Float = VehicleModelOrientation.initialPitch

    init(vehicle: TeslaVehicle) {
        self.vehicle = vehicle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        configureScene()
        configureOverlay()
        bindThemeChanges()
        updateCameraPosition(animated: false)
    }

    private func configureView() {
        view.backgroundColor = AppColors.modelViewerBackground

        sceneView.translatesAutoresizingMaskIntoConstraints = false
        sceneView.backgroundColor = .clear
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = true
        sceneView.defaultCameraController.interactionMode = .orbitTurntable
        sceneView.defaultCameraController.inertiaEnabled = true
        sceneView.defaultCameraController.maximumVerticalAngle = 85
        sceneView.defaultCameraController.minimumVerticalAngle = -85

        view.addSubview(sceneView)

        NSLayoutConstraint.activate([
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureScene() {
        let scene = SCNScene()
        sceneView.scene = scene

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 100
        scene.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.light?.intensity = 1450
        lightNode.position = SCNVector3(x: 0, y: 8, z: 8)
        scene.rootNode.addChildNode(lightNode)

        let secondaryLightNode = SCNNode()
        secondaryLightNode.light = SCNLight()
        secondaryLightNode.light?.type = .omni
        secondaryLightNode.light?.intensity = 950
        secondaryLightNode.position = SCNVector3(x: -6, y: 3, z: -5)
        scene.rootNode.addChildNode(secondaryLightNode)

        let ambientNode = SCNNode()
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 420
        scene.rootNode.addChildNode(ambientNode)

        if let assetURL = AppResourceProvider.shared.url(for: vehicle.modelAssetPath),
           let modelScene = try? SCNScene(url: assetURL, options: nil) {
            modelScene.rootNode.childNodes.forEach { modelRootNode.addChildNode($0) }
            normalize(modelRootNode, fitSize: SCNVector3(x: 10.4, y: 4.2, z: 6.6))
            scene.rootNode.addChildNode(modelRootNode)
        }
    }

    private func configureOverlay() {
        configureCloseButton()
        configureHintLabel()
        configureArrowButtons()
    }

    private func configureCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = AppColors.primaryText
        closeButton.backgroundColor = AppColors.modelViewerControlBackground
        closeButton.layer.cornerRadius = Layout.buttonSize / 2
        closeButton.layer.borderWidth = 1
        closeButton.layer.borderColor = AppColors.modelViewerControlBorder.cgColor
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)

        view.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: Layout.buttonSize),
            closeButton.heightAnchor.constraint(equalToConstant: Layout.buttonSize)
        ])
    }

    private func configureHintLabel() {
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.text = vehicle.displayName
        hintLabel.textColor = AppColors.mapOverlaySubtitle
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.textAlignment = .center
        hintLabel.backgroundColor = AppColors.modelViewerHintBackground
        hintLabel.contentInsets = UIEdgeInsets(top: 7, left: 18, bottom: 7, right: 18)
        hintLabel.numberOfLines = 1
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.layer.cornerRadius = Layout.hintHeight / 2
        hintLabel.layer.masksToBounds = true

        view.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            hintLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            hintLabel.heightAnchor.constraint(equalToConstant: Layout.hintHeight)
        ])
    }

    private func configureArrowButtons() {
        let buttonConfigs: [(UIButton, String, Selector)] = [
            (upButton, "chevron.up", #selector(didTapUp)),
            (downButton, "chevron.down", #selector(didTapDown)),
            (leftButton, "chevron.left", #selector(didTapLeft)),
            (rightButton, "chevron.right", #selector(didTapRight))
        ]

        buttonConfigs.forEach { button, imageName, action in
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setImage(UIImage(systemName: imageName), for: .normal)
            button.tintColor = AppColors.primaryText
            button.backgroundColor = AppColors.modelViewerControlBackground
            button.layer.cornerRadius = Layout.buttonSize / 2
            button.layer.borderWidth = 1
            button.layer.borderColor = AppColors.modelViewerControlBorder.cgColor
            button.addTarget(self, action: action, for: .touchUpInside)
            view.addSubview(button)
        }

        NSLayoutConstraint.activate([
            upButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 88),
            upButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            upButton.widthAnchor.constraint(equalToConstant: Layout.buttonSize),
            upButton.heightAnchor.constraint(equalToConstant: Layout.buttonSize),

            downButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            downButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            downButton.widthAnchor.constraint(equalToConstant: Layout.buttonSize),
            downButton.heightAnchor.constraint(equalToConstant: Layout.buttonSize),

            leftButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            leftButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            leftButton.widthAnchor.constraint(equalToConstant: Layout.buttonSize),
            leftButton.heightAnchor.constraint(equalToConstant: Layout.buttonSize),

            rightButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            rightButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            rightButton.widthAnchor.constraint(equalToConstant: Layout.buttonSize),
            rightButton.heightAnchor.constraint(equalToConstant: Layout.buttonSize)
        ])
    }

    private func bindThemeChanges() {
        themeCancellable = ThemeProvider.shared.$theme
            .sink { [weak self] _ in
                self?.applyCurrentTheme()
            }
    }

    private func applyCurrentTheme() {
        view.backgroundColor = AppColors.modelViewerBackground
        closeButton.tintColor = AppColors.primaryText
        closeButton.backgroundColor = AppColors.modelViewerControlBackground
        closeButton.layer.borderColor = AppColors.modelViewerControlBorder.cgColor
        hintLabel.textColor = AppColors.mapOverlaySubtitle
        hintLabel.backgroundColor = AppColors.modelViewerHintBackground

        [upButton, downButton, leftButton, rightButton].forEach { button in
            button.tintColor = AppColors.primaryText
            button.backgroundColor = AppColors.modelViewerControlBackground
            button.layer.borderColor = AppColors.modelViewerControlBorder.cgColor
        }
    }

    private func updateCameraPosition(animated: Bool) {
        let clampedPitch = max(-Layout.pitchLimit, min(Layout.pitchLimit, pitch))
        pitch = clampedPitch

        let x = Layout.cameraDistance * cos(clampedPitch) * sin(yaw)
        let y = Layout.cameraDistance * sin(clampedPitch)
        let z = Layout.cameraDistance * cos(clampedPitch) * cos(yaw)
        let targetPosition = SCNVector3(x, y, z)

        if animated {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.25
            cameraNode.position = targetPosition
            cameraNode.look(at: SCNVector3Zero)
            SCNTransaction.commit()
        } else {
            cameraNode.position = targetPosition
            cameraNode.look(at: SCNVector3Zero)
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
    private func didTapClose() {
        dismiss(animated: true)
    }

    @objc
    private func didTapUp() {
        pitch += Layout.angleStep
        updateCameraPosition(animated: true)
    }

    @objc
    private func didTapDown() {
        pitch -= Layout.angleStep
        updateCameraPosition(animated: true)
    }

    @objc
    private func didTapLeft() {
        yaw -= Layout.angleStep
        updateCameraPosition(animated: true)
    }

    @objc
    private func didTapRight() {
        yaw += Layout.angleStep
        updateCameraPosition(animated: true)
    }
}
