//
//  BlomixUIButtonStyle.swift
//  Blomix
//
//  Source de vérité unique pour le style et le comportement de TOUS les boutons du jeu
//  (UIKit et SpriteKit). Modifier ce fichier propage les changements partout.
//
//  Pour les boutons UIKit : utiliser `BlomixUIButton()` au lieu de `UIButton(type: .system)`.
//  L'animation press/release est gérée dans la sous-classe via beginTracking/endTracking,
//  sans aucune interférence avec le dispatch target-action habituel.
//

import SpriteKit
import UIKit

// MARK: - Style constants

@MainActor
enum BlomixUIDestinationButtonStyle {

    // MARK: - Couleurs

    static let backgroundColor = UIColor(
        red: CGFloat(0x23) / 255,
        green: CGFloat(0x23) / 255,
        blue: CGFloat(0x23) / 255,
        alpha: 1
    )

    static let borderColor = UIColor(
        red: CGFloat(0x44) / 255,
        green: CGFloat(0x44) / 255,
        blue: CGFloat(0x44) / 255,
        alpha: 1
    )

    // MARK: - Géométrie (UIKit ET SpriteKit)

    /// Rayon des coins arrondis — partagé UIKit + SpriteKit.
    static let cornerRadius: CGFloat = 10
    /// Padding horizontal intérieur (texte → bord) — partagé UIKit + SpriteKit.
    static let padH: CGFloat = 20
    /// Padding vertical intérieur (texte → bord) — partagé UIKit + SpriteKit.
    static let padV: CGFloat = 10

    // MARK: - Animation press/release (UIKit ET SpriteKit)

    // ── Appui ────────────────────────────────────────────────────────────────
    /// Échelle à l'état appuyé.
    static let pressScale: CGFloat = 0.92
    /// Translation vers le bas en pts lors de l'appui (simule l'enfoncement).
    static let pressTranslateY: CGFloat = 3
    /// Durée de la phase d'appui.
    static let pressAnimDuration: TimeInterval = 0.07

    // ── Relâchement ──────────────────────────────────────────────────────────
    /// Échelle maximale de l'overshoot au relâchement.
    static let releaseOvershootScale: CGFloat = 1.05
    /// Durée de la phase d'overshoot (scale 1.05, retour position).
    static let releasePhase1Duration: TimeInterval = 0.09
    /// Durée de la phase de stabilisation (1.05 → 1.0).
    static let releasePhase2Duration: TimeInterval = 0.07
    /// Durée totale du relâchement (≈ 0.16 s).
    static var releaseTotalDuration: TimeInterval { releasePhase1Duration + releasePhase2Duration }

    // MARK: - Typographie

    /// Épaisseur d'une ligne de 1 pixel physique (comme en CSS).
    static var hairlineBorderWidth: CGFloat {
        1.0 / max(UIScreen.main.scale, 1)
    }

    /// Taille unique pour tous les boutons de navigation (« Fermer », etc.) + pastilles SpriteKit.
    static let navigationTitleFontSize: CGFloat = 17

    static func titleFont(size: CGFloat, weight: UIFont.Weight = .medium) -> UIFont {
        BlomixTypography.uiFont(size: size, weight: weight)
    }

    // MARK: - Application du style

    /// Même style que le bouton Fermer : `navigationTitleFontSize` + poids au choix.
    static func applyNavigationButtonStyle(to button: UIButton, weight: UIFont.Weight = .medium) {
        apply(to: button, fontSize: navigationTitleFontSize, weight: weight)
    }

    /// Texte blanc, police du projet, fond #232323, bordure 1 px #444444.
    static func apply(to button: UIButton, fontSize: CGFloat, weight: UIFont.Weight = .medium, cornerRadius: CGFloat = -1) {
        let cr = cornerRadius >= 0 ? cornerRadius : Self.cornerRadius
        if #available(iOS 15.0, *) {
            button.configuration = nil
        }
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.backgroundColor = backgroundColor
        button.titleLabel?.font = titleFont(size: fontSize, weight: weight)
        button.layer.cornerRadius = cr
        button.layer.borderWidth = hairlineBorderWidth
        button.layer.borderColor = borderColor.cgColor
        button.clipsToBounds = true
    }

    /// Fond #232323 pour `SKShapeNode` / pastilles d'accueil (aligné sur UIKit).
    static let startScreenChipFillSKColor = SKColor(cgColor: backgroundColor.cgColor)
}

// MARK: - Notification

extension Notification.Name {
    /// Postée par `BlomixUIButton` sur `.touchUpInside` — GameScene joue le son de tap.
    static let blomixButtonTap = Notification.Name("blomixButtonTap")
    /// Postée juste AVANT dismiss(animated:) — GameScene masque l'overlay statique pour
    /// que la transition modale révèle le fond noir plutôt que l'accueil figé.
    static let blomixModalWillDismiss = Notification.Name("blomixModalWillDismiss")
    /// Postée dans la completion de dismiss — GameScene reconstruit l'accueil avec animations.
    static let blomixModalDidDismiss = Notification.Name("blomixModalDidDismiss")
}

// MARK: - BlomixUIButton

/// Remplacement drop-in de `UIButton(type: .system)` : gère automatiquement
/// l'animation press/release (scale + translation) via le tracking UIControl,
/// sans interférer avec les target-action enregistrés sur le bouton.
@MainActor
class BlomixUIButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTapSound()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTapSound()
    }

    private func setupTapSound() {
        addTarget(self, action: #selector(blomixPostTapSound), for: .touchUpInside)
    }

    @objc private func blomixPostTapSound() {
        NotificationCenter.default.post(name: .blomixButtonTap, object: nil)
    }

    // MARK: - Tracking

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let result = super.beginTracking(touch, with: event)
        if result { blomixAnimatePress() }
        return result
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        blomixAnimateRelease()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        blomixAnimateRelease()
    }

    // MARK: - CALayer animations
    //
    // On anime uniquement la COUCHE DE PRÉSENTATION (CALayer) et non le transform UIView.
    // Le modèle layer reste à .identity → AutoLayout ne voit jamais de frame modifié
    // → aucune perturbation du UIStackView ni de la mise en page environnante.

    private static let blomixCAKey = "blomixBtn"

    /// Valeur courante du scale dans la couche de présentation (ou modèle si pas d'animation).
    private func blomixCurrentScale() -> Double {
        let src = layer.presentation() ?? layer
        return (src.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1.0
    }

    /// Valeur courante de la translation Y dans la couche de présentation.
    private func blomixCurrentTranslateY() -> Double {
        let src = layer.presentation() ?? layer
        return (src.value(forKeyPath: "transform.translation.y") as? NSNumber)?.doubleValue ?? 0.0
    }

    private func blomixAnimatePress() {
        let fromScale = blomixCurrentScale()
        let fromDY    = blomixCurrentTranslateY()
        // On retire les animations en cours APRÈS avoir capturé l'état de présentation.
        layer.removeAnimation(forKey: Self.blomixCAKey)

        let toScale = Double(BlomixUIDestinationButtonStyle.pressScale)
        let toDY    = Double(BlomixUIDestinationButtonStyle.pressTranslateY)
        let dur     = BlomixUIDestinationButtonStyle.pressAnimDuration

        let scaleAnim              = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue        = fromScale
        scaleAnim.toValue          = toScale
        scaleAnim.timingFunction   = CAMediaTimingFunction(name: .easeIn)

        let txAnim                 = CABasicAnimation(keyPath: "transform.translation.y")
        txAnim.fromValue           = fromDY
        txAnim.toValue             = toDY
        txAnim.timingFunction      = CAMediaTimingFunction(name: .easeIn)

        let group                  = CAAnimationGroup()
        group.animations           = [scaleAnim, txAnim]
        group.duration             = dur
        group.fillMode             = .forwards
        group.isRemovedOnCompletion = false

        layer.add(group, forKey: Self.blomixCAKey)
    }

    private func blomixAnimateRelease() {
        let fromScale = blomixCurrentScale()
        let fromDY    = blomixCurrentTranslateY()
        layer.removeAnimation(forKey: Self.blomixCAKey)

        let overshoot = Double(BlomixUIDestinationButtonStyle.releaseOvershootScale)
        let dur1      = BlomixUIDestinationButtonStyle.releasePhase1Duration
        let dur2      = BlomixUIDestinationButtonStyle.releasePhase2Duration
        let total     = dur1 + dur2
        let t1        = NSNumber(value: dur1 / total)

        let easeOut      = CAMediaTimingFunction(name: .easeOut)
        let easeInOut    = CAMediaTimingFunction(name: .easeInEaseOut)

        let scaleAnim              = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values           = [fromScale, overshoot, 1.0]
        scaleAnim.keyTimes         = [0, t1, 1.0]
        scaleAnim.timingFunctions  = [easeOut, easeInOut]

        let txAnim                 = CAKeyframeAnimation(keyPath: "transform.translation.y")
        txAnim.values              = [fromDY, 0.0, 0.0]
        txAnim.keyTimes            = [0, t1, 1.0]
        txAnim.timingFunctions     = [easeOut, easeInOut]

        let group                  = CAAnimationGroup()
        group.animations           = [scaleAnim, txAnim]
        group.duration             = total
        group.fillMode             = .forwards
        group.isRemovedOnCompletion = false

        layer.add(group, forKey: Self.blomixCAKey)
    }
}
