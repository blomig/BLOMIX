//
//  BlomixAmbientBlocksView.swift
//  Blomix
//
//  Animation de mini-blox colorés qui montent aléatoirement en arrière-plan.
//  Utilisée sur tous les écrans UIKit (réglages, classement, lobby PvP, etc.)
//  en dehors du jeu actif.  S'insère en premier subview (index 0) pour rester
//  derrière tout le contenu existant.
//

import UIKit

@MainActor
final class BlomixAmbientBlocksView: UIView {

    enum Density {
        /// Accueil / GO / record / lobby.
        case high
        /// Réglages / crédits / classements (moins de bruit sur le texte).
        case low
    }

    var density: Density = .high

    /// Fantômes sur la plaque (accueil SK + tous les fonds UIKit / Game Over).
    nonisolated static let travelingBlockAlpha: CGFloat = 0.20

    /// Aligné sur SpriteKit (`GameScene.spawnAmbientBlock`) : max 18 pt, min = max/2.
    private let blockSizeMax: CGFloat = 18
    private var blockSizeMin: CGFloat { blockSizeMax / 2 }
    private let colorKeys = ["red", "blue", "green", "yellow", "purple", "orange"]
    private var spawnTimer: Timer?
    private var styleObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    // MARK: Cycle de vie

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if styleObserver == nil {
                styleObserver = NotificationCenter.default.addObserver(
                    forName: .blomixVisualStyleDidChange,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.subviews.forEach { $0.removeFromSuperview() }
                    }
                }
            }
            scheduleNextSpawn()
        } else {
            spawnTimer?.invalidate()
            spawnTimer = nil
            if let styleObserver {
                NotificationCenter.default.removeObserver(styleObserver)
                self.styleObserver = nil
            }
        }
    }

    // MARK: Spawn

    private func scheduleNextSpawn() {
        spawnTimer?.invalidate()
        let delay: Double
        switch density {
        case .high: delay = Double.random(in: 0.125...1.0)
        case .low:  delay = Double.random(in: 0.55...2.2)
        }
        spawnTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.window != nil else { return }
                self.spawnBlock()
                self.scheduleNextSpawn()
            }
        }
    }

    private func spawnBlock() {
        let w = bounds.width
        let h = bounds.height
        guard w > blockSizeMax * 2, h > 0 else { return }

        let blockSize = CGFloat.random(in: blockSizeMin...blockSizeMax)

        let xInset = blockSize / 2 + 8
        let maxX = w - xInset - blockSize
        guard maxX > xInset else { return }
        let x = CGFloat.random(in: xInset...maxX)

        // Même dispersion de vitesses que la version SpriteKit.
        let baseSpeed: CGFloat = 100
        let speed = baseSpeed * CGFloat.random(in: (1.0 / 3.0)...3.0)
        let distance = h + blockSize * 2
        let duration = TimeInterval(distance / speed)

        if BlomixInkChrome.isActive {
            let variant = Int.random(in: 0..<BlomixInkChrome.confettiCount)
            let block = UIImageView(image: BlomixInkChrome.confettiImage(variant: variant).withRenderingMode(.alwaysTemplate))
            block.tintColor = BlomixInkChrome.watermarkUI
            block.alpha = CGFloat.random(in: BlomixInkChrome.plateAlpha)
            block.bounds = CGRect(x: 0, y: 0, width: blockSize, height: blockSize)
            block.center = CGPoint(x: x + blockSize / 2, y: h + blockSize / 2)
            let startAngle = CGFloat.random(in: -0.6...0.6)
            block.transform = CGAffineTransform(rotationAngle: startAngle)
            addSubview(block)
            let spin = CGFloat.random(in: 0.35...0.70) * (Bool.random() ? 1 : -1)
            let reduced = UIAccessibility.isReduceMotionEnabled
            UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear]) {
                block.center.y = -blockSize * 1.5
                if !reduced {
                    block.transform = CGAffineTransform(rotationAngle: startAngle + spin)
                }
            } completion: { _ in
                block.removeFromSuperview()
            }
            return
        }

        let colorKey = colorKeys.randomElement() ?? "blue"
        let color = BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: colorKey)
                    ?? UIColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1)

        // Forme alignée SpriteKit : carré plein, pas de coins / bordure.
        let block = UIView()
        block.backgroundColor = color
        block.layer.cornerRadius = 0
        block.alpha = Self.travelingBlockAlpha
        block.frame = CGRect(x: x, y: h, width: blockSize, height: blockSize)
        addSubview(block)

        UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear]) {
            block.frame.origin.y = -(blockSize * 2)
        } completion: { _ in
            block.removeFromSuperview()
        }
    }
}

// MARK: - Extension UIViewController

/// Convenience : insère un `BlomixAmbientBlocksView` en fond de vue (index 0).
extension UIViewController {
    func addAmbientBlocksBackground(density: BlomixAmbientBlocksView.Density = .high) {
        let bg = BlomixAmbientBlocksView()
        bg.density = density
        bg.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(bg, at: 0)
        NSLayoutConstraint.activate([
            bg.topAnchor.constraint(equalTo: view.topAnchor),
            bg.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bg.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
