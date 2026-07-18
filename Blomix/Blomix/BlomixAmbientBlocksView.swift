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

    private let blockSize: CGFloat = 18
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
        let delay = Double.random(in: 0.25...2.0)
        spawnTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, self.window != nil else { return }
            self.spawnBlock()
            self.scheduleNextSpawn()
        }
    }

    private func spawnBlock() {
        let w = bounds.width
        let h = bounds.height
        guard w > blockSize * 2, h > 0 else { return }

        let colorKey = colorKeys.randomElement() ?? "blue"
        let color = BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: colorKey)
                    ?? UIColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1)

        let block = UIView()
        block.backgroundColor = color
        block.layer.cornerRadius = 3
        block.layer.borderWidth = 0.5
        block.layer.borderColor = (BlomixAppearance.isDark
            ? UIColor(white: 1, alpha: 0.25)
            : UIColor(white: 0, alpha: 0.12)).cgColor
        block.alpha = 0.85

        let xInset = blockSize / 2 + 8
        let x = CGFloat.random(in: xInset...(w - xInset - blockSize))
        block.frame = CGRect(x: x, y: h, width: blockSize, height: blockSize)
        addSubview(block)

        // Même dispersion de vitesses que la version SpriteKit.
        let baseSpeed: CGFloat = 100
        let speed = baseSpeed * CGFloat.random(in: (1.0 / 3.0)...3.0)
        let distance = h + blockSize * 2
        let duration = TimeInterval(distance / speed)

        UIView.animate(withDuration: duration, delay: 0, options: [.curveLinear]) {
            block.frame.origin.y = -(self.blockSize * 2)
        } completion: { _ in
            block.removeFromSuperview()
        }
    }
}

// MARK: - Extension UIViewController

/// Convenience : insère un `BlomixAmbientBlocksView` en fond de vue (index 0).
extension UIViewController {
    func addAmbientBlocksBackground() {
        let bg = BlomixAmbientBlocksView()
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
