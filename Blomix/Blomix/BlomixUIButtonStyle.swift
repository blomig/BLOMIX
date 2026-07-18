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

    // MARK: - Couleurs (délèguent vers BlomixAppearance)

    static var backgroundColor: UIColor { BlomixAppearance.chipFill }
    static var borderColor: UIColor { BlomixAppearance.chipBorder }
    static var titleColor: UIColor { BlomixAppearance.chipTitle }

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

    // MARK: - "Vie" des boutons : couleur réactive, ombre portée, ressort

    /// Fond légèrement décalé à l'état appuyé.
    static var pressedBackgroundColor: UIColor { BlomixAppearance.chipPressedFill }
    /// Même valeur en SKColor pour les boutons SpriteKit.
    static var pressedBackgroundSKColor: SKColor { BlomixAppearance.chipPressedFillSK }

    /// Opacité de l'ombre portée au repos (UIKit ; nécessite clipsToBounds = false).
    static var shadowOpacity: Float { BlomixAppearance.chipShadowOpacity }
    /// Décalage de l'ombre vers le bas — donne un effet « surface surélevée ».
    static let shadowOffset          = CGSize(width: 0, height: 3)
    /// Rayon du flou de l'ombre.
    static let shadowRadius: CGFloat = 5

    /// Amortissement du ressort de relâchement (CASpringAnimation) — 13 = rebond léger perceptible.
    static let springDamping: CGFloat         = 13
    /// Rigidité du ressort.
    static let springStiffness: CGFloat       = 260
    /// Masse de la particule virtuelle du ressort (1 = comportement standard).
    static let springMass: CGFloat            = 1
    /// Vélocité initiale injectée au ressort (crée l'overshoot naturel).
    static let springInitialVelocity: CGFloat = 10

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

    /// Texte / fond / bordure selon le thème chrome courant.
    static func apply(to button: UIButton, fontSize: CGFloat, weight: UIFont.Weight = .medium, cornerRadius: CGFloat = -1) {
        let cr = cornerRadius >= 0 ? cornerRadius : Self.cornerRadius
        if #available(iOS 15.0, *) {
            button.configuration = nil
        }
        button.setTitleColor(titleColor, for: .normal)
        button.tintColor = titleColor
        button.backgroundColor = backgroundColor
        button.titleLabel?.font = titleFont(size: fontSize, weight: weight)
        button.layer.cornerRadius = cr
        button.layer.borderWidth  = hairlineBorderWidth
        button.layer.borderColor  = borderColor.cgColor
        // clipsToBounds = false pour laisser l'ombre portée se dessiner hors des limites du bouton.
        button.clipsToBounds      = false
        button.layer.shadowColor   = UIColor.black.cgColor
        button.layer.shadowOpacity = shadowOpacity
        button.layer.shadowOffset  = shadowOffset
        button.layer.shadowRadius  = shadowRadius
    }

    /// Fond pastille pour `SKShapeNode` / pastilles d'accueil (aligné sur UIKit).
    static var startScreenChipFillSKColor: SKColor { BlomixAppearance.chipFillSK }
}

// MARK: - Notification

extension Notification.Name {
    /// Postée par `BlomixUIButton` sur `.touchUpInside` — GameScene joue le son de tap.
    static let blomixButtonTap = Notification.Name("blomixButtonTap")
    /// Postée juste AVANT dismiss(animated:) — GameScene masque l'overlay statique pour
    /// que la transition modale révèle le fond scène plutôt que l'accueil figé.
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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty else { return }
        // Fournir un shadowPath explicite : Core Animation dessine l'ombre sans recalcul coûteux.
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: layer.cornerRadius
        ).cgPath
    }

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
    private static let haptic = UIImpactFeedbackGenerator(style: .light)

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
        Self.haptic.impactOccurred()
        Self.haptic.prepare()
        let fromScale = blomixCurrentScale()
        let fromDY    = blomixCurrentTranslateY()
        layer.removeAnimation(forKey: Self.blomixCAKey)

        let toScale = Double(BlomixUIDestinationButtonStyle.pressScale)
        let toDY    = Double(BlomixUIDestinationButtonStyle.pressTranslateY)
        let dur     = BlomixUIDestinationButtonStyle.pressAnimDuration

        // ── Scale + translate (CAAnimation explicite) ────────────────────────
        let scaleAnim            = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue      = fromScale
        scaleAnim.toValue        = toScale
        scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)

        let txAnim               = CABasicAnimation(keyPath: "transform.translation.y")
        txAnim.fromValue         = fromDY
        txAnim.toValue           = toDY
        txAnim.timingFunction    = CAMediaTimingFunction(name: .easeIn)

        let group                    = CAAnimationGroup()
        group.animations             = [scaleAnim, txAnim]
        group.duration               = dur
        group.fillMode               = .forwards
        group.isRemovedOnCompletion  = false
        layer.add(group, forKey: Self.blomixCAKey)

        // ── Fond + ombre (UIView animation implicite) ────────────────────────
        UIView.animate(withDuration: dur, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.backgroundColor        = BlomixUIDestinationButtonStyle.pressedBackgroundColor
            self.layer.shadowOpacity    = 0
            self.layer.shadowOffset     = .zero
        }
    }

    private func blomixAnimateRelease() {
        let fromScale = blomixCurrentScale()
        let fromDY    = blomixCurrentTranslateY()
        layer.removeAnimation(forKey: Self.blomixCAKey)

        // ── CASpringAnimation : scale + translate ────────────────────────────
        // Le ressort produit un léger overshoot organique sans courbe codée en dur.
        let d = BlomixUIDestinationButtonStyle.springDamping
        let k = BlomixUIDestinationButtonStyle.springStiffness
        let m = BlomixUIDestinationButtonStyle.springMass
        let v = BlomixUIDestinationButtonStyle.springInitialVelocity

        let scaleAnim = CASpringAnimation(keyPath: "transform.scale")
        scaleAnim.damping         = d
        scaleAnim.stiffness       = k
        scaleAnim.mass            = m
        scaleAnim.initialVelocity = v
        scaleAnim.fromValue       = fromScale
        scaleAnim.toValue         = 1.0

        let txAnim = CASpringAnimation(keyPath: "transform.translation.y")
        txAnim.damping         = d
        txAnim.stiffness       = k
        txAnim.mass            = m
        txAnim.initialVelocity = -v * 0.6   // kick vers le haut
        txAnim.fromValue       = fromDY
        txAnim.toValue         = 0.0

        let springDur = max(scaleAnim.settlingDuration, txAnim.settlingDuration)

        let group                   = CAAnimationGroup()
        group.animations            = [scaleAnim, txAnim]
        group.duration              = springDur
        group.fillMode              = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: Self.blomixCAKey)

        // ── Fond + ombre (UIView animation implicite) ────────────────────────
        UIView.animate(withDuration: 0.22, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.backgroundColor     = BlomixUIDestinationButtonStyle.backgroundColor
            self.layer.shadowOpacity = BlomixUIDestinationButtonStyle.shadowOpacity
            self.layer.shadowOffset  = BlomixUIDestinationButtonStyle.shadowOffset
        }
    }
}
