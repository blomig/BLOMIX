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
    /// Emprise tactile / layout (hors descendants ambiants clipés dans le puits).
    var layoutSize: CGSize { buttonSize }
    private var wellTimeOffset: Float = 0
    /// Encre : le masque du liseré. Le scale d’appui ne touche pas le libellé.
    private weak var inkRimMask: SKSpriteNode?
    /// Figé à la construction. Le Classique ne passe jamais par le chemin Encre.
    private var usesInkChrome = false
    /// `false` : la gouttière est la piste neutre. `true` : le dégradé du skin.
    private var wellShowsSkin = true
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
        cornerRadius: CGFloat = -1,
        wellInset: CGFloat = -1
    ) {
        super.init()
        self.name = name
        assemble(
            size: size,
            cornerRadius: cornerRadius,
            text: text,
            labelName: labelName,
            fontSize: fontSize,
            systemName: nil,
            wellInset: wellInset
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
        iconPointSize: CGFloat = 18,
        wellInset: CGFloat = -1
    ) {
        buttonSize = size
        wellTimeOffset = Self.timeOffset(for: name ?? text)
        let maxCorner = min(size.width, size.height) / 2
        let resolvedCorner = min(cornerRadius >= 0 ? cornerRadius : Self.cornerRadius, maxCorner)
        let inset = wellInset >= 0 ? wellInset : BlomixUIDestinationButtonStyle.wellInset(for: size)
        let resolvedFontSize = fontSize > 0 ? fontSize : Self.defaultFontSize
        usesInkChrome = BlomixInkChrome.isActive
        if usesInkChrome {
            assembleInk(
                size: size,
                cornerRadius: resolvedCorner,
                text: text,
                labelName: labelName,
                fontSize: resolvedFontSize,
                systemName: systemName,
                iconPointSize: iconPointSize
            )
            installChromeObservers()
            return
        }

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
            // Chelsea Market (Encre) : les capitales portent un peu haut, on les descend d’1 pt.
            let opticalY: CGFloat = BlomixVisualStyle.current == .new ? -1 : 1
            label.position = CGPoint(x: 0, y: opticalY)
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

        installChromeObservers()
    }

    /// Papier washi + liseré. Le puits `blomixWell` reste le crop des échos,
    /// masqué par l’anneau peint : le fill garde la taille du bouton.
    private func assembleInk(
        size: CGSize,
        cornerRadius: CGFloat,
        text: String,
        labelName: String?,
        fontSize: CGFloat,
        systemName: String?,
        iconPointSize: CGFloat
    ) {
        let clip = SKCropNode()
        clip.zPosition = 0
        let clipMask = SKSpriteNode(
            texture: BlomixButtonRelief.roundedRectMaskTexture(size: size, cornerRadius: cornerRadius),
            size: size
        )
        clip.maskNode = clipMask
        addChild(clip)

        let paper = SKSpriteNode(
            texture: BlomixInkChrome.paperTexture(size: size, cornerRadius: cornerRadius),
            size: size
        )
        paper.name = "blomixInkPaper"
        paper.zPosition = 0
        clip.addChild(paper)

        let well = SKCropNode()
        well.name = "blomixWell"
        well.zPosition = 1
        well.userData = NSMutableDictionary()
        well.userData?["cornerRadius"] = cornerRadius
        well.userData?["timeOffset"] = wellTimeOffset
        let rim = SKSpriteNode(
            texture: BlomixInkChrome.brushRingTexture(size: size, cornerRadius: cornerRadius),
            size: size
        )
        well.maskNode = rim
        inkRimMask = rim
        let fill = SKSpriteNode(texture: BlomixSkinGradient.shaderBaseTexture, size: size)
        fill.name = "blomixWellFill"
        BlomixSkinGradient.applyShader(to: fill, timeOffset: wellTimeOffset)
        well.addChild(fill)
        clip.addChild(well)
        wellNode = well

        let inner = SKNode()
        inner.name = "blomixCapsuleContent"
        inner.zPosition = 2
        addChild(inner)
        capsuleContentNode = inner

        if !text.isEmpty || labelName != nil {
            let label = SKLabelNode(text: text)
            label.name = labelName
            label.fontName = BlomixTypeRole.inkPostScriptName
            label.fontSize = fontSize
            label.fontColor = BlomixInkChrome.inkGray
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 0, y: -1)
            label.zPosition = 1
            inner.addChild(label)
            labelNode = label
        }

        if let systemName {
            let iconSide = min(size.width, size.height) * 0.46
            let icon = SKSpriteNode(
                texture: BlomixAppearance.chromeSymbolTexture(
                    systemName: systemName,
                    pointSize: iconPointSize,
                    canvasSide: max(iconSide, 18),
                    tint: BlomixInkChrome.inkGrayUI
                )
            )
            icon.name = "blomixButtonIcon"
            icon.size = CGSize(width: iconSide, height: iconSide)
            icon.zPosition = 1
            icon.userData = NSMutableDictionary()
            icon.userData?["systemName"] = systemName
            inner.addChild(icon)
        }
    }

    private func installChromeObservers() {
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
        if usesInkChrome {
            if wellShowsSkin {
                if let fill = wellFillSprite {
                    BlomixSkinGradient.applyShader(to: fill, timeOffset: wellTimeOffset)
                }
            } else {
                applyNeutralWell()
            }
            return
        }
        BlomixSkinGradient.refreshWellNode(self, timeOffset: wellTimeOffset)
        if wellShowsSkin {
            if let fill = wellFillSprite {
                BlomixSkinGradient.applyShader(to: fill, timeOffset: wellTimeOffset)
            }
        } else {
            applyNeutralWell()
        }
    }

    /// Gouttière du skin, ou piste neutre. Les portes de l’accueil restent colorées.
    func setWellShowsSkin(_ shows: Bool) {
        wellShowsSkin = shows
        refreshSkinGradient()
    }

    private func applyNeutralWell() {
        guard let fill = wellFillSprite else { return }
        fill.shader = nil
        fill.colorBlendFactor = 1
        fill.color = BlomixAppearance.progressTrackSK
    }

    private var wellFillSprite: SKSpriteNode? {
        wellNode?.childNode(withName: "blomixWellFill") as? SKSpriteNode
    }

    /// Fade chrome + puits ensemble. Le fill shader n’hérite pas l’alpha du chip.
    func runChromeFadeSequence(fadeIn: TimeInterval, hold: TimeInterval, fadeOut: TimeInterval) {
        alpha = 0
        wellFillSprite?.alpha = 0
        let appear = SKAction.fadeIn(withDuration: fadeIn)
        let vanish = SKAction.fadeOut(withDuration: fadeOut)
        let holdWait = SKAction.wait(forDuration: hold)
        run(SKAction.sequence([appear, holdWait, vanish, SKAction.removeFromParent()]))
        if let fill = wellFillSprite {
            fill.run(SKAction.sequence([
                appear.copy() as! SKAction,
                holdWait.copy() as! SKAction,
                vanish.copy() as! SKAction,
            ]))
        }
    }

    /// Retire le shader GPU des puits invisibles (dropdown ☰ fermé).
    func setWellShaderEnabled(_ enabled: Bool) {
        guard let fill = wellNode?.childNode(withName: "blomixWellFill") as? SKSpriteNode else { return }
        if enabled {
            if usesInkChrome {
                fill.alpha = 1
                if wellShowsSkin {
                    BlomixSkinGradient.applyShader(to: fill, timeOffset: wellTimeOffset)
                } else {
                    applyNeutralWell()
                }
            } else {
                BlomixSkinGradient.applyShader(to: fill, timeOffset: wellTimeOffset)
            }
        } else {
            fill.shader = nil
            if usesInkChrome { fill.alpha = 0 }
        }
    }

    func refreshChrome() {
        if usesInkChrome {
            labelNode?.fontName = BlomixTypeRole.inkPostScriptName
            labelNode?.fontColor = BlomixInkChrome.inkGray
            if let icon = capsuleContentNode?.childNode(withName: "blomixButtonIcon") as? SKSpriteNode,
               let systemName = icon.userData?["systemName"] as? String {
                let side = icon.size.width
                icon.texture = BlomixAppearance.chromeSymbolTexture(
                    systemName: systemName,
                    pointSize: 18,
                    canvasSide: max(side, 18),
                    tint: BlomixInkChrome.inkGrayUI
                )
            }
            refreshSkinGradient()
            return
        }
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
        if wellNode != nil {
            refreshSkinGradient()
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
        if usesInkChrome {
            guard let rim = inkRimMask else { return }
            rim.removeAction(forKey: Self.pressActionKey)
            let spread = SKAction.scale(to: BlomixInkChrome.spreadScale, duration: BlomixInkChrome.spreadOutDuration)
            spread.timingMode = .easeOut
            rim.run(spread, withKey: Self.pressActionKey)
            return
        }
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
        if usesInkChrome {
            guard let rim = inkRimMask else { return }
            rim.removeAction(forKey: Self.pressActionKey)
            let back = SKAction.scale(to: 1, duration: BlomixInkChrome.spreadBackDuration)
            back.timingMode = .easeOut
            rim.run(back, withKey: Self.pressActionKey)
            return
        }
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
