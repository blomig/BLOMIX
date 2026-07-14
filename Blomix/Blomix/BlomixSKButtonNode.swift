//
//  BlomixSKButtonNode.swift
//  Blomix
//
//  Composant SpriteKit réutilisable pour tous les boutons du jeu (écran d'accueil,
//  game over, tutoriel…). Toutes les constantes de style proviennent de
//  `BlomixUIDestinationButtonStyle` — source de vérité unique.
//
//  Usage :
//    let btn = BlomixSKButtonNode(
//        name: "myButton",
//        labelName: "myButtonLabel",   // nil = pas de name sur le label
//        text: "JOUER",
//        size: CGSize(width: 160, height: 44),
//        fontSize: 17
//    )
//    btn.position = ...
//    parentNode.addChild(btn)
//
//  L'animation press/release est déclenchée depuis GameScene.touchesBegan/Ended
//  via `animatePressed()` / `animateReleased()`.
//

import SpriteKit

@MainActor
final class BlomixSKButtonNode: SKNode {

    // MARK: - Style constants (délèguent vers BlomixUIDestinationButtonStyle)

    /// Rayon des coins arrondis — lit la valeur globale.
    static var cornerRadius: CGFloat { BlomixUIDestinationButtonStyle.cornerRadius }
    /// Taille de police par défaut.
    static var defaultFontSize: CGFloat { BlomixUIDestinationButtonStyle.navigationTitleFontSize }
    /// Padding horizontal (texte → bord du fond).
    static var padH: CGFloat { BlomixUIDestinationButtonStyle.padH }
    /// Padding vertical (texte → bord du fond).
    static var padV: CGFloat { BlomixUIDestinationButtonStyle.padV }

    // MARK: - Sub-node access

    /// Nœud de fond (`SKShapeNode`) — exposé pour animations éventuelles.
    private(set) weak var backgroundNode: SKShapeNode?
    /// Nœud de libellé (`SKLabelNode`) — exposé pour mise à jour du texte.
    private(set) weak var labelNode: SKLabelNode?
    /// Nœud d'ombre portée — même chemin que `backgroundNode`, légèrement décalé vers le bas.
    private(set) weak var shadowNode: SKShapeNode?

    /// Couleurs de repos pour un bouton hero (accent skin) — restaurées après press/release.
    private var restingFillColor = BlomixUIDestinationButtonStyle.startScreenChipFillSKColor
    private var restingBorderColor = BlomixUIDestinationButtonStyle.borderColor
    private var restingBorderWidth = BlomixUIDestinationButtonStyle.hairlineBorderWidth

    // MARK: - Init

    /// Crée un bouton avec fond arrondi et libellé centré.
    /// - Parameters:
    ///   - name:         Identifiant du conteneur (utilisé par `touchesBegan` pour hit-test).
    ///   - labelName:    Identifiant du `SKLabelNode` (nil = pas de name sur le label).
    ///   - text:         Texte affiché.
    ///   - size:         Taille du fond (width × height).
    ///   - fontSize:     Taille de police (défaut : `defaultFontSize`).
    ///   - cornerRadius: Rayon des coins (défaut : `BlomixSKButtonNode.cornerRadius`).
    init(
        name: String,
        labelName: String? = nil,
        text: String,
        size: CGSize,
        fontSize: CGFloat = 0,
        cornerRadius: CGFloat = -1
    ) {
        super.init()

        self.name = name

        let resolvedFontSize = fontSize > 0      ? fontSize     : Self.defaultFontSize
        let resolvedCorner   = cornerRadius >= 0 ? cornerRadius : Self.cornerRadius

        // ── Fond arrondi ──────────────────────────────────────────────────────
        let rect = CGRect(
            x: -size.width  / 2,
            y: -size.height / 2,
            width:  size.width,
            height: size.height
        )
        let path = CGPath(
            roundedRect: rect,
            cornerWidth:  resolvedCorner,
            cornerHeight: resolvedCorner,
            transform: nil
        )
        // ── Ombre portée ──────────────────────────────────────────────────────
        let shadow = SKShapeNode(path: path)
        shadow.fillColor   = SKColor(white: 0, alpha: 0.28)
        shadow.strokeColor = .clear
        shadow.position    = CGPoint(x: 1, y: -4)
        shadow.zPosition   = -1
        addChild(shadow)
        shadowNode = shadow

        // ── Fond arrondi ──────────────────────────────────────────────────────
        let bg = SKShapeNode(path: path)
        bg.fillColor   = BlomixUIDestinationButtonStyle.startScreenChipFillSKColor
        bg.strokeColor = BlomixUIDestinationButtonStyle.borderColor
        bg.lineWidth   = BlomixUIDestinationButtonStyle.hairlineBorderWidth
        bg.zPosition   = 0
        addChild(bg)
        backgroundNode = bg
        restingFillColor   = bg.fillColor
        restingBorderColor = bg.strokeColor
        restingBorderWidth = bg.lineWidth

        // ── Libellé centré ────────────────────────────────────────────────────
        let label = SKLabelNode(text: text)
        label.name                    = labelName
        label.fontName                = BlomixTypography.shared.spriteKitFontName
        label.fontSize                = resolvedFontSize
        label.fontColor               = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .center
        label.position                = .zero
        label.zPosition               = 1
        addChild(label)
        labelNode = label
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Press / Release animation

    private static let pressActionKey = "blomixSKBtnPress"
    private static let haptic = UIImpactFeedbackGenerator(style: .light)

    /// Position enregistrée au moment de l'appui pour un retour précis.
    private var positionBeforePress: CGPoint?

    /// Joue l'animation d'appui : scale 0.92 + descente + fond éclairci + ombre compressée.
    func animatePressed() {
        Self.haptic.impactOccurred()
        Self.haptic.prepare()
        removeAction(forKey: Self.pressActionKey)
        positionBeforePress = position

        let s   = BlomixUIDestinationButtonStyle.pressScale
        let dy  = BlomixUIDestinationButtonStyle.pressTranslateY
        let dur = BlomixUIDestinationButtonStyle.pressAnimDuration

        let scaleDown = SKAction.scale(to: s, duration: dur)
        scaleDown.timingMode = .easeIn
        let moveDown = SKAction.moveBy(x: 0, y: -dy, duration: dur)
        moveDown.timingMode = .easeIn
        run(.group([scaleDown, moveDown]), withKey: Self.pressActionKey)

        // Fond légèrement plus clair (instantané — la durée de press est 70 ms).
        backgroundNode?.fillColor = BlomixUIDestinationButtonStyle.pressedBackgroundSKColor
        // L'ombre se comprime naturellement via le scale parent ;
        // on réduit aussi son alpha pour accentuer l'effet d'enfoncement.
        shadowNode?.alpha = 0.05
    }

    /// Joue l'animation de relâchement : ressort 3 phases + restauration fond + ombre.
    /// Appelé depuis GameScene.touchesEnded / touchesCancelled.
    func animateReleased() {
        removeAction(forKey: Self.pressActionKey)
        let origin = positionBeforePress ?? position
        positionBeforePress = nil

        let dur1 = BlomixUIDestinationButtonStyle.releasePhase1Duration

        // ── Ressort 3 phases (overshoot → undershoot → stabilisation) ────────
        // Produit un rebond organique sans courbe prédéfinie.
        let scaleUp  = SKAction.scale(to: 1.07, duration: dur1)
        scaleUp.timingMode  = .easeOut
        let moveBack = SKAction.move(to: origin, duration: dur1)
        moveBack.timingMode = .easeOut
        let phase1 = SKAction.group([scaleUp, moveBack])

        let underShoot = SKAction.scale(to: 0.98, duration: 0.06)
        underShoot.timingMode = .easeInEaseOut

        let settle = SKAction.scale(to: 1.0, duration: 0.04)
        settle.timingMode = .easeInEaseOut

        run(.sequence([phase1, underShoot, settle]), withKey: Self.pressActionKey)

        // Restaure le fond et l'ombre.
        backgroundNode?.fillColor   = restingFillColor
        backgroundNode?.strokeColor = restingBorderColor
        backgroundNode?.lineWidth   = restingBorderWidth
        let restoreAlpha = SKAction.fadeAlpha(to: 1, duration: dur1)
        restoreAlpha.timingMode = .easeOut
        shadowNode?.run(restoreAlpha)
    }

    // MARK: - Helpers

    /// Accentue un bouton hero (bordure teintée skin + fond légèrement teinté).
    func applyHeroAccent(borderColor: SKColor, fillTint: SKColor? = nil) {
        restingBorderColor = borderColor
        restingBorderWidth = 2.0
        backgroundNode?.strokeColor = borderColor
        backgroundNode?.lineWidth   = restingBorderWidth
        if let fillTint {
            restingFillColor = fillTint
            backgroundNode?.fillColor = fillTint
        }
    }

    /// Met à jour le texte affiché sans reconstruire le nœud.
    func setText(_ text: String) {
        labelNode?.text = text
    }

    /// Calcule la taille minimale nécessaire pour afficher `text` à `fontSize`
    /// avec les marges standard (`padH` / `padV`), sans dépasser `maxWidth`.
    static func fittingSize(for text: String, fontSize: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        let font = BlomixTypography.uiFont(size: fontSize, weight: .regular)
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let w = min(maxWidth, ceil(measured.width)  + padH * 2)
        let h = ceil(measured.height) + padV * 2
        return CGSize(width: max(w, 88), height: max(h, 40))
    }

    /// Calcule la taille commune pour un ensemble de libellés (la plus grande),
    /// sans dépasser `maxWidth`. Utile pour aligner plusieurs boutons de même largeur.
    static func unifiedSize(for texts: [String], fontSize: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        let font = BlomixTypography.uiFont(size: fontSize, weight: .regular)
        var maxW: CGFloat = 0
        var maxH: CGFloat = 0
        for t in texts {
            let s = (t as NSString).size(withAttributes: [.font: font])
            maxW = max(maxW, ceil(s.width))
            maxH = max(maxH, ceil(s.height))
        }
        let w = min(maxWidth, maxW + padH * 2)
        let h = maxH + padV * 2
        return CGSize(width: max(w, 88), height: max(h, 40))
    }
}
