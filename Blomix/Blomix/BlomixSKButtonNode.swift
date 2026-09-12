//
//  BlomixSKButtonNode.swift
//  Blomix
//
//  Bouton SpriteKit : puits (dégradé skin) + capsule chrome. L’appui scale
//  uniquement la capsule. Style : `BlomixUIDestinationButtonStyle`.
//

import SpriteKit

@MainActor
final class BlomixSKButtonNode: SKNode {

    // MARK: - Style constants

    static var cornerRadius: CGFloat { BlomixUIDestinationButtonStyle.cornerRadius }
    static var defaultFontSize: CGFloat { BlomixUIDestinationButtonStyle.navigationTitleFontSize }
    static var padH: CGFloat { BlomixUIDestinationButtonStyle.padH }
    static var padV: CGFloat { BlomixUIDestinationButtonStyle.padV }

    // MARK: - Sub-node access

    /// Contenu cliquable (capsule + libellé + icône) — seul ce nœud scale à l’appui.
    private(set) weak var capsuleContentNode: SKNode?
    private(set) weak var backgroundNode: SKShapeNode?
    private(set) weak var labelNode: SKLabelNode?
    private(set) weak var wellNode: SKCropNode?
    private weak var contactShadowNode: SKShapeNode?
    private weak var bevelNode: SKSpriteNode?
    private var capsuleSize: CGSize = .zero
    private var capsuleRadius: CGFloat = 8

    private var buttonSize: CGSize = .zero
    private var wellTimeOffset: Float = 0
    private var skinObserver: NSObjectProtocol?

    private var restingFillColor = BlomixAppearance.chipFillSK
    private var restingBorderColor = SKColor.clear
    private var restingBorderWidth: CGFloat = 0

    // MARK: - Init texte

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
        assemble(
            size: size,
            cornerRadius: cornerRadius,
            text: text,
            labelName: labelName,
            fontSize: fontSize,
            systemName: nil
        )
    }

    /// Puits + capsule + SF Symbol (icônes accueil, hamburger).
    init(
        name: String,
        size: CGSize,
        systemName: String,
        iconPointSize: CGFloat = 18,
        cornerRadius: CGFloat = -1
    ) {
        super.init()
        self.name = name
        assemble(
            size: size,
            cornerRadius: cornerRadius,
            text: "",
            labelName: nil,
            fontSize: 0,
            systemName: systemName,
            iconPointSize: iconPointSize
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Construction

    private func assemble(
        size: CGSize,
        cornerRadius: CGFloat,
        text: String,
        labelName: String?,
        fontSize: CGFloat,
        systemName: String?,
        iconPointSize: CGFloat = 18
    ) {
        buttonSize = size
        wellTimeOffset = Self.timeOffset(for: name ?? text)
        let maxCorner = min(size.width, size.height) / 2
        let resolvedCorner = min(cornerRadius >= 0 ? cornerRadius : Self.cornerRadius, maxCorner)
        let inset = BlomixUIDestinationButtonStyle.wellInset(for: size)
        let resolvedFontSize = fontSize > 0 ? fontSize : Self.defaultFontSize

        let well = BlomixSkinGradient.makeWellNode(
            size: size,
            cornerRadius: resolvedCorner,
            timeOffset: wellTimeOffset
        )
        well.zPosition = 0
        addChild(well)
        wellNode = well

        let inner = SKNode()
        inner.name = "blomixCapsuleContent"
        inner.zPosition = 1
        addChild(inner)
        capsuleContentNode = inner

        let capSize = CGSize(
            width: max(8, size.width - inset * 2),
            height: max(8, size.height - inset * 2)
        )
        let isCircle = resolvedCorner >= maxCorner - 0.5
        let capRadius = isCircle
            ? min(capSize.width, capSize.height) / 2
            : max(4, resolvedCorner - inset * 0.45)
        capsuleSize = capSize
        capsuleRadius = capRadius
        let capRect = CGRect(
            x: -capSize.width / 2,
            y: -capSize.height / 2,
            width: capSize.width,
            height: capSize.height
        )
        let capPath = CGPath(
            roundedRect: capRect,
            cornerWidth: capRadius,
            cornerHeight: capRadius,
            transform: nil
        )
        let shadow = SKShapeNode(path: capPath)
        shadow.name = "blomixCapsuleShadow"
        shadow.fillColor = .black
        shadow.strokeColor = .clear
        shadow.alpha = BlomixButtonRelief.contactShadowAlpha
        shadow.position = CGPoint(x: 0, y: -BlomixButtonRelief.contactShadowOffsetY)
        shadow.zPosition = -1
        inner.addChild(shadow)
        contactShadowNode = shadow

        let bg = SKShapeNode(path: capPath)
        bg.fillColor = BlomixAppearance.chipFillSK
        bg.strokeColor = .clear
        bg.lineWidth = 0
        bg.zPosition = 0
        inner.addChild(bg)
        backgroundNode = bg
        restingFillColor = bg.fillColor
        restingBorderColor = .clear
        restingBorderWidth = 0

        let bevel = SKSpriteNode(
            texture: BlomixButtonRelief.capsuleBevelTexture(size: capSize, cornerRadius: capRadius),
            size: capSize
        )
        bevel.name = "blomixCapsuleBevel"
        bevel.zPosition = 0.5
        inner.addChild(bevel)
        bevelNode = bevel

        if !text.isEmpty || labelName != nil {
            let label = SKLabelNode(text: text)
            label.name = labelName
            label.fontName = BlomixTypography.fontName(.display)
            label.fontSize = resolvedFontSize
            label.fontColor = BlomixAppearance.chipTitleSK
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            // Changa One : le centre optique est un cran bas.
            label.position = CGPoint(x: 0, y: 1)
            label.zPosition = 1
            inner.addChild(label)
            labelNode = label
        }

        if let systemName {
            let iconSide = min(capSize.width, capSize.height) * 0.58
            let icon = SKSpriteNode(
                texture: BlomixAppearance.chromeSymbolTexture(
                    systemName: systemName,
                    pointSize: iconPointSize,
                    canvasSide: max(iconSide, 18)
                )
            )
            icon.name = "blomixButtonIcon"
            icon.size = CGSize(width: iconSide, height: iconSide)
            icon.zPosition = 1
            icon.userData = NSMutableDictionary()
            icon.userData?["systemName"] = systemName
            inner.addChild(icon)
        }

        skinObserver = NotificationCenter.default.addObserver(
            forName: .blomixSkinDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSkinGradient()
            }
        }
        _ = NotificationCenter.default.addObserver(
            forName: .blomixAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshChrome()
            }
        }
    }

    func refreshSkinGradient() {
        BlomixSkinGradient.invalidateShaderCache()
        BlomixSkinGradient.refreshWellNode(self, timeOffset: wellTimeOffset)
    }

    func refreshChrome() {
        backgroundNode?.fillColor = BlomixAppearance.chipFillSK
        restingFillColor = BlomixAppearance.chipFillSK
        labelNode?.fontColor = BlomixAppearance.chipTitleSK
        contactShadowNode?.alpha = BlomixButtonRelief.contactShadowAlpha
        contactShadowNode?.fillColor = .black
        if let bevelNode, capsuleSize.width > 0 {
            bevelNode.texture = BlomixButtonRelief.capsuleBevelTexture(
                size: capsuleSize,
                cornerRadius: capsuleRadius
            )
        }
        if let well = wellNode {
            BlomixSkinGradient.refreshWellNode(well, timeOffset: wellTimeOffset)
        }
        if let icon = capsuleContentNode?.childNode(withName: "blomixButtonIcon") as? SKSpriteNode,
           let systemName = icon.userData?["systemName"] as? String {
            let side = icon.size.width
            icon.texture = BlomixAppearance.chromeSymbolTexture(
                systemName: systemName,
                pointSize: 18,
                canvasSide: max(side, 18)
            )
        }
    }

    private static func timeOffset(for name: String) -> Float {
        var h: UInt64 = 5381
        for b in name.utf8 { h = ((h << 5) &+ h) &+ UInt64(b) }
        return Float(h % 1000) / 1000
    }

    // MARK: - Press / Release

    private static let pressActionKey = "blomixSKBtnPress"
    private static let haptic = UIImpactFeedbackGenerator(style: .light)

    func animatePressed() {
        Self.haptic.impactOccurred()
        Self.haptic.prepare()
        guard let inner = capsuleContentNode else { return }
        inner.removeAction(forKey: Self.pressActionKey)

        let s = BlomixUIDestinationButtonStyle.pressScale
        let dur = BlomixUIDestinationButtonStyle.pressAnimDuration
        let scaleDown = SKAction.scale(to: s, duration: dur)
        scaleDown.timingMode = .easeIn
        inner.run(scaleDown, withKey: Self.pressActionKey)
        let fade = SKAction.fadeAlpha(to: BlomixButtonRelief.contactShadowAlphaPressed, duration: dur)
        fade.timingMode = .easeIn
        contactShadowNode?.run(fade)
    }

    func animateReleased() {
        guard let inner = capsuleContentNode else { return }
        inner.removeAction(forKey: Self.pressActionKey)

        let dur1 = BlomixUIDestinationButtonStyle.releasePhase1Duration
        let overshoot = BlomixUIDestinationButtonStyle.releaseOvershootScale

        let scaleUp = SKAction.scale(to: overshoot, duration: dur1)
        scaleUp.timingMode = .easeOut
        let settle = SKAction.scale(to: 1.0, duration: BlomixUIDestinationButtonStyle.releasePhase2Duration)
        settle.timingMode = .easeInEaseOut
        inner.run(.sequence([scaleUp, settle]), withKey: Self.pressActionKey)
        let fade = SKAction.fadeAlpha(to: BlomixButtonRelief.contactShadowAlpha, duration: dur1)
        fade.timingMode = .easeOut
        contactShadowNode?.run(fade)
    }

    // MARK: - Helpers

    /// 6.7 : le puits skin remplace l’ancien accent hero (bordure teintée). No-op conservé.
    func applyHeroAccent(borderColor: SKColor, fillTint: SKColor? = nil) {
        _ = borderColor
        _ = fillTint
    }

    func setText(_ text: String) {
        labelNode?.text = text
    }

    static func fittingSize(for text: String, fontSize: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        unifiedSize(for: [text], fontSize: fontSize, maxWidth: maxWidth)
    }

    static func unifiedSize(for texts: [String], fontSize: CGFloat, maxWidth: CGFloat = .greatestFiniteMagnitude) -> CGSize {
        let font = BlomixTypography.displayFont(size: fontSize)
        var maxW: CGFloat = 0
        var maxH: CGFloat = 0
        for t in texts {
            let s = (t as NSString).size(withAttributes: [.font: font])
            maxW = max(maxW, ceil(s.width))
            maxH = max(maxH, ceil(s.height))
        }
        let gutter = BlomixUIDestinationButtonStyle.wellInset * 2
        let w = min(maxWidth, maxW + padH * 2 + gutter)
        let h = maxH + padV * 2 + gutter
        return CGSize(width: max(w, 88), height: max(h, 44))
    }
}
