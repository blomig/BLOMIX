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

    /// Aligné sur SpriteKit (`GameScene.spawnAmbientBlock`) : max 18 pt, min = max/2.
    private let blockSizeMax: CGFloat = 18
    private var blockSizeMin: CGFloat { blockSizeMax / 2 }
    private let colorKeys = ["red", "blue", "green", "yellow", "purple", "orange"]
    private var spawnTimer: Timer?

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
            scheduleNextSpawn()
        } else {
            spawnTimer?.invalidate()
            spawnTimer = nil
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

        let colorKey = colorKeys.randomElement() ?? "blue"
        let color = BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: colorKey)
                    ?? UIColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1)

        // Forme alignée SpriteKit : carré plein, pas de coins / bordure.
        let block = UIView()
        block.backgroundColor = color
        block.layer.cornerRadius = 0
        block.alpha = 0.92

        let xInset = blockSize / 2 + 8
        let maxX = w - xInset - blockSize
        guard maxX > xInset else { return }
        let x = CGFloat.random(in: xInset...maxX)
        block.frame = CGRect(x: x, y: h, width: blockSize, height: blockSize)
        addSubview(block)

        // Même dispersion de vitesses que la version SpriteKit.
        let baseSpeed: CGFloat = 100
        let speed = baseSpeed * CGFloat.random(in: (1.0 / 3.0)...3.0)
        let distance = h + blockSize * 2
        let duration = TimeInterval(distance / speed)

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
