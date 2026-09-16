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

    /// Rayon des coins du puits — partagé UIKit + SpriteKit.
    static let cornerRadius: CGFloat = 14
    /// Bande colorée visible autour de la capsule (gouttière du puits).
    static let wellInset: CGFloat = 6
    static let wellInsetCompact: CGFloat = 4
    static func wellInset(for size: CGSize) -> CGFloat {
        min(size.width, size.height) < 48 ? wellInsetCompact : wellInset
    }
    /// Padding horizontal intérieur (texte → bord de la capsule).
    static let padH: CGFloat = 20
    /// Padding vertical intérieur (texte → bord de la capsule).
    static let padV: CGFloat = 10

    // MARK: - Animation press/release (UIKit ET SpriteKit)

    // ── Appui ────────────────────────────────────────────────────────────────
    /// Échelle de la capsule à l'état appuyé (le puits ne bouge pas).
    static let pressScale: CGFloat = 0.90
    /// Conservé pour compat ; l’enfoncement 6.7 est un scale, pas une translation.
    static let pressTranslateY: CGFloat = 0
    /// Durée de la phase d'appui.
    static let pressAnimDuration: TimeInterval = 0.07

    // ── Relâchement ──────────────────────────────────────────────────────────
    /// Échelle maximale de l'overshoot au relâchement (calmé vs 1,07 historique).
    static let releaseOvershootScale: CGFloat = 1.04
    /// Durée de la phase d'overshoot.
    static let releasePhase1Duration: TimeInterval = 0.09
    /// Durée de la phase de stabilisation.
    static let releasePhase2Duration: TimeInterval = 0.07
    /// Durée totale du relâchement (≈ 0.16 s).
    static var releaseTotalDuration: TimeInterval { releasePhase1Duration + releasePhase2Duration }
    /// Attendre la remontée visuelle avant de changer d’écran.
    static var actionCommitDelay: TimeInterval { releaseTotalDuration + 0.04 }

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

    static func titleFont(size: CGFloat, weight: UIFont.Weight = .semibold) -> UIFont {
        BlomixTypography.displayFont(size: size, weight: weight)
    }

    // MARK: - Application du style

    /// Même style que le bouton Fermer : `navigationTitleFontSize` + poids au choix.
    static func applyNavigationButtonStyle(to button: UIButton, weight: UIFont.Weight = .semibold) {
        apply(to: button, fontSize: navigationTitleFontSize, weight: weight)
    }

    /// Puits skin + capsule chrome selon le thème courant.
    static func apply(to button: UIButton, fontSize: CGFloat, weight: UIFont.Weight = .semibold, cornerRadius: CGFloat = -1) {
        let cr = cornerRadius >= 0 ? cornerRadius : Self.cornerRadius
        button.configuration = nil
        button.setTitleColor(titleColor, for: .normal)
        button.tintColor = titleColor
        button.backgroundColor = .clear
        button.titleLabel?.font = titleFont(size: fontSize, weight: weight)
        button.layer.cornerRadius = cr
        button.layer.borderWidth = 0
        button.layer.borderColor = UIColor.clear.cgColor
        button.clipsToBounds = false
        button.layer.shadowOpacity = 0
        button.layer.shadowRadius = 0
        button.layer.shadowPath = nil
        if let blomix = button as? BlomixUIButton {
            blomix.installWellIfNeeded(cornerRadius: cr)
            blomix.refreshWellChrome()
        } else {
            button.backgroundColor = backgroundColor
            button.layer.borderWidth = hairlineBorderWidth
            button.layer.borderColor = borderColor.cgColor
        }
    }

    /// Padding intérieur sans `contentEdgeInsets` (déprécié iOS 15 / ignoré avec Configuration).
    static func applyContentInsets(_ insets: UIEdgeInsets, to button: UIButton) {
        if let blomix = button as? BlomixUIButton {
            blomix.blomixContentInsets = insets
        } else {
            // Secours hors BlomixUIButton : configuration minimale (pas le style principal).
            var config = button.configuration ?? .plain()
            config.contentInsets = NSDirectionalEdgeInsets(
                top: insets.top,
                leading: insets.left,
                bottom: insets.bottom,
                trailing: insets.right
            )
            button.configuration = config
        }
    }

    /// Fond pastille pour `SKShapeNode` / pastilles d'accueil (aligné sur UIKit).
    static var startScreenChipFillSKColor: SKColor { BlomixAppearance.chipFillSK }

    /// Distingue l’option sélectionnée (onglets classement, Sombre/Clair).
    /// Clair : non sélectionné plus atténué — le liseré seul ne suffisait pas sur le puits coloré.
    static func applySelectionChrome(to button: UIButton, selected: Bool) {
        button.alpha = selected ? 1 : (BlomixAppearance.isDark ? 0.70 : 0.55)
        if selected {
            button.layer.borderWidth = 2.0
            button.layer.borderColor = BlomixAppearance.primaryText.cgColor
        } else {
            button.layer.borderWidth = 0
            button.layer.borderColor = UIColor.clear.cgColor
        }
    }
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

    /// Remplace `contentEdgeInsets` (déprécié iOS 15) tout en restant hors `UIButton.Configuration`.
    var blomixContentInsets: UIEdgeInsets = .zero {
        didSet {
            guard oldValue != blomixContentInsets else { return }
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    fileprivate let wellView = UIView()
    fileprivate let capsuleView = UIView()
    fileprivate let wellGradient = BlomixSkinGradientLayer()
    fileprivate let wellInnerShadow = CALayer()
    fileprivate let capsuleBevel = CALayer()
    private var wellInstalled = false
    private var wellCornerRadius: CGFloat = BlomixUIDestinationButtonStyle.cornerRadius
    private var lastReliefSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTapSound()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTapSound()
    }

    fileprivate func installWellIfNeeded(cornerRadius: CGFloat) {
        wellCornerRadius = cornerRadius
        guard !wellInstalled else {
            wellView.layer.cornerRadius = cornerRadius
            return
        }
        wellInstalled = true
        wellView.isUserInteractionEnabled = false
        capsuleView.isUserInteractionEnabled = false
        wellView.clipsToBounds = true
        wellView.layer.cornerRadius = cornerRadius
        wellView.layer.addSublayer(wellGradient)
        wellInnerShadow.contentsGravity = .resize
        wellInnerShadow.actions = ["contents": NSNull()]
        wellView.layer.addSublayer(wellInnerShadow)
        BlomixSkinGradientClock.shared.register(wellGradient)
        capsuleView.backgroundColor = BlomixUIDestinationButtonStyle.backgroundColor
        capsuleView.clipsToBounds = false
        capsuleView.layer.masksToBounds = false
        capsuleView.layer.shadowColor = UIColor.black.cgColor
        capsuleView.layer.shadowOffset = CGSize(width: 0, height: BlomixButtonRelief.contactShadowOffsetY)
        capsuleView.layer.shadowRadius = 2.2
        capsuleView.layer.shadowOpacity = Float(BlomixButtonRelief.contactShadowAlpha)
        capsuleBevel.contentsGravity = .resize
        capsuleBevel.masksToBounds = true
        capsuleBevel.actions = ["contents": NSNull()]
        capsuleView.layer.addSublayer(capsuleBevel)
        insertSubview(wellView, at: 0)
        insertSubview(capsuleView, at: 1)
    }

    fileprivate func refreshWellChrome() {
        capsuleView.backgroundColor = BlomixUIDestinationButtonStyle.backgroundColor
        wellView.layer.cornerRadius = wellCornerRadius
        capsuleView.layer.shadowOpacity = Float(BlomixButtonRelief.contactShadowAlpha)
        lastReliefSize = .zero
        setNeedsLayout()
    }

    /// Agrandit le bouton autour du titre centré (équivalent pratique de contentEdgeInsets
    /// sans APIs dépréciées ni UIButton.Configuration).
    override var intrinsicContentSize: CGSize {
        let base = super.intrinsicContentSize
        guard blomixContentInsets != .zero else { return base }
        var width = base.width
        var height = base.height
        if width != UIView.noIntrinsicMetric {
            width += blomixContentInsets.left + blomixContentInsets.right
        }
        if height != UIView.noIntrinsicMetric {
            height += blomixContentInsets.top + blomixContentInsets.bottom
        }
        return CGSize(width: width, height: height)
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
        wellView.frame = bounds
        wellGradient.frame = wellView.bounds
        wellInnerShadow.frame = wellView.bounds
        wellInnerShadow.cornerRadius = wellCornerRadius
        let inset = BlomixUIDestinationButtonStyle.wellInset(for: bounds.size)
        capsuleView.frame = bounds.insetBy(dx: inset, dy: inset)
        let capR = max(4, wellCornerRadius - inset * 0.45)
        capsuleView.layer.cornerRadius = capR
        capsuleView.layer.shadowPath = UIBezierPath(
            roundedRect: capsuleView.bounds,
            cornerRadius: capR
        ).cgPath
        capsuleBevel.frame = capsuleView.bounds
        capsuleBevel.cornerRadius = capR
        let reliefKey = CGSize(width: bounds.width.rounded(), height: bounds.height.rounded())
        if reliefKey != lastReliefSize, bounds.width > 1, bounds.height > 1 {
            lastReliefSize = reliefKey
            wellInnerShadow.contents = BlomixButtonRelief.wellInnerShadowImage(
                size: bounds.size,
                cornerRadius: wellCornerRadius
            ).cgImage
            capsuleBevel.contents = BlomixButtonRelief.capsuleBevelImage(
                size: capsuleView.bounds.size,
                cornerRadius: capR
            ).cgImage
        }
        bringSubviewToFront(capsuleView)
        if let imageView { bringSubviewToFront(imageView) }
        if let titleLabel { bringSubviewToFront(titleLabel) }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let result = super.beginTracking(touch, with: event)
        if result { blomixAnimatePress() }
        return result
    }

    private var blomixDeferringTouchUp = false

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        let inside = isTouchInside
        blomixAnimateRelease()
        blomixDeferringTouchUp = inside
        super.endTracking(touch, with: event)
        blomixDeferringTouchUp = false
    }

    override func cancelTracking(with event: UIEvent?) {
        blomixDeferringTouchUp = false
        super.cancelTracking(with: event)
        blomixAnimateRelease()
    }

    override func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        if blomixDeferringTouchUp, action != #selector(blomixPostTapSound) {
            let sel = action
            let tgt = target as AnyObject?
            let delay = BlomixUIDestinationButtonStyle.actionCommitDelay
            isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak tgt] in
                guard let self else { return }
                self.isUserInteractionEnabled = true
                self.blomixSendActionNow(sel, to: tgt)
            }
            return
        }
        super.sendAction(action, to: target, for: event)
    }

    private func blomixSendActionNow(_ action: Selector, to target: AnyObject?) {
        super.sendAction(action, to: target, for: nil)
    }

    // MARK: - CALayer animations
    //
    // On anime uniquement la COUCHE DE PRÉSENTATION (CALayer) et non le transform UIView.
    // Le modèle layer reste à .identity → AutoLayout ne voit jamais de frame modifié
    // → aucune perturbation du UIStackView ni de la mise en page environnante.

    private static let blomixCAKey = "blomixBtn"
    private static let haptic = UIImpactFeedbackGenerator(style: .light)

    /// Scale courant de la capsule (présentation ou modèle).
    private func blomixCapsuleScale() -> Double {
        let src = capsuleView.layer.presentation() ?? capsuleView.layer
        return (src.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1.0
    }

    private func blomixAddCapsuleScale(from: Double, to: Double, duration: TimeInterval, timing: CAMediaTimingFunctionName) {
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: timing)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        for target in blomixCapsuleTargets() {
            target.removeAnimation(forKey: Self.blomixCAKey)
            target.add(anim, forKey: Self.blomixCAKey)
        }
    }

    private func blomixCapsuleTargets() -> [CALayer] {
        var layers = [capsuleView.layer]
        if let titleLabel { layers.append(titleLabel.layer) }
        if let imageView { layers.append(imageView.layer) }
        return layers
    }

    private func blomixAnimatePress() {
        Self.haptic.impactOccurred()
        Self.haptic.prepare()
        let fromScale = blomixCapsuleScale()
        let toScale = Double(BlomixUIDestinationButtonStyle.pressScale)
        blomixAddCapsuleScale(
            from: fromScale,
            to: toScale,
            duration: BlomixUIDestinationButtonStyle.pressAnimDuration,
            timing: .easeIn
        )
        let dur = BlomixUIDestinationButtonStyle.pressAnimDuration
        CATransaction.begin()
        CATransaction.setAnimationDuration(dur)
        capsuleView.layer.shadowOpacity = Float(BlomixButtonRelief.contactShadowAlphaPressed)
        CATransaction.commit()
    }

    private func blomixAnimateRelease() {
        let fromScale = blomixCapsuleScale()
        let d = BlomixUIDestinationButtonStyle.springDamping
        let k = BlomixUIDestinationButtonStyle.springStiffness
        let m = BlomixUIDestinationButtonStyle.springMass
        let v = BlomixUIDestinationButtonStyle.springInitialVelocity

        let scaleAnim = CASpringAnimation(keyPath: "transform.scale")
        scaleAnim.damping = d
        scaleAnim.stiffness = k
        scaleAnim.mass = m
        scaleAnim.initialVelocity = v
        scaleAnim.fromValue = fromScale
        scaleAnim.toValue = 1.0
        scaleAnim.fillMode = .forwards
        scaleAnim.isRemovedOnCompletion = false
        scaleAnim.duration = scaleAnim.settlingDuration

        for target in blomixCapsuleTargets() {
            target.removeAnimation(forKey: Self.blomixCAKey)
            target.add(scaleAnim, forKey: Self.blomixCAKey)
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        capsuleView.layer.shadowOpacity = Float(BlomixButtonRelief.contactShadowAlpha)
        CATransaction.commit()
    }
}

// MARK: - Interrupteur chrome BLOMIX (pas UISwitch système)

/// Piste gouttière (dégradé skin ON / `progressTrack` OFF) + pastille chrome, haptique light.
@MainActor
final class BlomixChromeSwitch: UIControl {

    var isOn: Bool = false {
        didSet { guard oldValue != isOn else { return }; applyState(animated: true) }
    }

    private let track = UIView()
    private let gradient = BlomixSkinGradientLayer()
    private let lip = CALayer()
    private let knob = UIView()
    private var knobLeading: NSLayoutConstraint?
    private var lastLipSize: CGSize = .zero
    private static let haptic = UIImpactFeedbackGenerator(style: .light)
    private static let knobSize: CGFloat = 26

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        track.isUserInteractionEnabled = false
        knob.isUserInteractionEnabled = false
        track.clipsToBounds = true
        track.translatesAutoresizingMaskIntoConstraints = false
        knob.translatesAutoresizingMaskIntoConstraints = false

        gradient.actions = ["contents": NSNull()]
        track.layer.addSublayer(gradient)
        BlomixSkinGradientClock.shared.register(gradient)
        lip.contentsGravity = .resize
        lip.actions = ["contents": NSNull()]
        track.layer.addSublayer(lip)

        knob.layer.borderWidth = BlomixUIDestinationButtonStyle.hairlineBorderWidth
        knob.layer.shadowColor = UIColor.black.cgColor
        knob.layer.shadowOffset = CGSize(width: 0, height: 1.5)
        knob.layer.shadowRadius = 1.6
        knob.layer.shadowOpacity = Float(BlomixButtonRelief.contactShadowAlpha)

        addSubview(track)
        addSubview(knob)

        let leading = knob.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 3)
        knobLeading = leading

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 52),
            heightAnchor.constraint(equalToConstant: 32),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: topAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            knob.centerYAnchor.constraint(equalTo: track.centerYAnchor),
            knob.widthAnchor.constraint(equalToConstant: Self.knobSize),
            knob.heightAnchor.constraint(equalToConstant: Self.knobSize),
            leading,
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)

        _ = NotificationCenter.default.addObserver(
            forName: .blomixAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshChrome() }
        }
        _ = NotificationCenter.default.addObserver(
            forName: .blomixSkinDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshChrome() }
        }

        applyState(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cap = bounds.height / 2
        track.layer.cornerRadius = cap
        gradient.frame = track.bounds
        lip.frame = track.bounds
        let lipKey = CGSize(width: bounds.width.rounded(), height: bounds.height.rounded())
        if lipKey != lastLipSize, bounds.width > 1, bounds.height > 1 {
            lastLipSize = lipKey
            lip.contents = BlomixButtonRelief.wellInnerShadowImage(
                size: bounds.size,
                cornerRadius: cap
            ).cgImage
        }
        knob.layer.cornerRadius = Self.knobSize / 2
        knob.layer.shadowPath = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: Self.knobSize, height: Self.knobSize)),
            cornerRadius: Self.knobSize / 2
        ).cgPath
        bringSubviewToFront(knob)
        updateKnobTravel()
    }

    @objc private func tapped() {
        isOn.toggle()
        Self.haptic.impactOccurred()
        Self.haptic.prepare()
        sendActions(for: .valueChanged)
    }

    private func updateKnobTravel() {
        let travel = track.bounds.width - Self.knobSize - 6
        knobLeading?.constant = isOn ? max(3, travel) : 3
    }

    private func applyState(animated: Bool) {
        let changes = {
            self.gradient.opacity = self.isOn ? 1 : 0
            self.track.backgroundColor = self.isOn ? .clear : BlomixAppearance.progressTrack
            self.knob.backgroundColor = BlomixAppearance.chipFill
            self.knob.layer.borderColor = BlomixAppearance.chipBorder.cgColor
            self.knob.layer.shadowOpacity = Float(BlomixButtonRelief.contactShadowAlpha)
            self.updateKnobTravel()
            self.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseInOut], animations: changes)
        } else {
            changes()
        }
    }

    func refreshChrome() {
        lastLipSize = .zero
        applyState(animated: false)
        setNeedsLayout()
    }
}
