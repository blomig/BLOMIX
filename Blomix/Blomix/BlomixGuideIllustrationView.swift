//
//  BlomixGuideIllustrationView.swift
//  Blomix
//
//  Pictos procéduraux du guide (6.4) : palette skin joueur.
//  Bombe / Magix = vrais sprites SpriteKit (shader + particules + symbole).
//

import SpriteKit
import UIKit

enum BlomixGuideIllustrationKind: Int, CaseIterable {
    case blox, brix, line, bombs, magix, score, duel
}

/// Zone ~1/3 de carte : dessin jeu, sans texte localisé.
@MainActor
final class BlomixGuideIllustrationView: UIView {

    let kind: BlomixGuideIllustrationKind
    let magixKind: MagixKind
    private var skView: SKView?

    init(kind: BlomixGuideIllustrationKind, magixKind: MagixKind = .chromax) {
        self.kind = kind
        self.magixKind = magixKind
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerRadius = 10
        backgroundColor = BlomixAppearance.emptyCell
        switch kind {
        case .bombs, .magix:
            embedSpritePreview()
        default:
            break
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 108)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        skView?.frame = bounds
        if kind != .bombs, kind != .magix {
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        switch kind {
        case .blox:  drawBlox(in: rect)
        case .brix:  drawBrix(in: rect)
        case .line:  drawLine(in: rect)
        case .score: drawScore(in: rect)
        case .duel:  drawDuel(in: rect)
        case .bombs, .magix:
            break
        }
    }

    // MARK: - SK previews (bombe / Magix)

    private func embedSpritePreview() {
        let view = SKView(frame: bounds)
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Les shaders SK ratent souvent si la vue est transparente.
        view.allowsTransparency = false
        view.backgroundColor = BlomixAppearance.emptyCell
        view.isAsynchronous = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 30
        let scene = GuideSpritePreviewScene(kind: kind, magixKind: magixKind)
        scene.scaleMode = .resizeFill
        scene.backgroundColor = SKColor(cgColor: BlomixAppearance.emptyCell.cgColor)
        view.presentScene(scene)
        addSubview(view)
        skView = view
    }

    // MARK: - UIKit pictos

    private func bloxColors() -> [UIColor] {
        let keys = BlomixSkinCatalog.bloxDisplayOrder
        return keys.compactMap { BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: $0) }
    }

    private func drawRoundedBlock(in ctx: CGContext, rect: CGRect, color: UIColor) {
        ctx.setFillColor(color.cgColor)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 3)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
    }

    private func drawBlox(in rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let colors = bloxColors()
        let fill = colors.first ?? UIColor.systemBlue
        let cell: CGFloat = 18
        let gap: CGFloat = 2
        let step = cell + gap
        let offsets: [(CGFloat, CGFloat)] = [
            (0, 0), (1, 0), (2, 0),
            (0, 1), (1, 1),
            (1, -1),
        ]
        let minX = offsets.map(\.0).min() ?? 0
        let maxX = offsets.map(\.0).max() ?? 0
        let minY = offsets.map(\.1).min() ?? 0
        let maxY = offsets.map(\.1).max() ?? 0
        let gridW = (maxX - minX + 1) * step - gap
        let gridH = (maxY - minY + 1) * step - gap
        let origin = CGPoint(
            x: rect.midX - gridW / 2 - minX * step,
            y: rect.midY - gridH / 2 - minY * step
        )
        for (dx, dy) in offsets {
            let r = CGRect(
                x: origin.x + dx * step,
                y: origin.y + dy * step,
                width: cell,
                height: cell
            )
            drawRoundedBlock(in: ctx, rect: r, color: fill)
        }
    }

    private func drawBrix(in rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let side: CGFloat = 44
        let block = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )
        drawRoundedBlock(in: ctx, rect: block, color: BlomixSkinCatalog.shared.priksUIColor())
        let digit = "5" as NSString
        let font = BlomixTypography.displayFont(size: 26, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: BlomixSkinCatalog.shared.priksDigitUIColor(),
        ]
        let size = digit.size(withAttributes: attrs)
        digit.draw(
            at: CGPoint(x: block.midX - size.width / 2, y: block.midY - size.height / 2 - 1),
            withAttributes: attrs
        )
    }

    private func drawLine(in rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let colors = bloxColors()
        let cols = 4
        let cell: CGFloat = 16
        let gap: CGFloat = 2
        let totalW = CGFloat(cols) * cell + CGFloat(cols - 1) * gap
        let startX = rect.midX - totalW / 2
        let y = rect.maxY - 22
        for i in 0..<cols {
            let color = colors.indices.contains(i) ? colors[i] : (colors.first ?? .gray)
            let r = CGRect(x: startX + CGFloat(i) * (cell + gap), y: y, width: cell, height: cell / 2)
            ctx.saveGState()
            ctx.addRect(r)
            ctx.clip()
            drawRoundedBlock(
                in: ctx,
                rect: CGRect(x: r.minX, y: r.minY - cell / 2, width: cell, height: cell),
                color: color
            )
            ctx.restoreGState()
        }
    }

    private func drawScore(in rect: CGRect) {
        let text = "+20" as NSString
        let font = BlomixTypography.displayFont(size: 28, weight: .bold)
        let color = bloxColors().first ?? BlomixAppearance.primaryText
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attrs)
        text.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }

    private func drawDuel(in rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let barW: CGFloat = 18
        let barH: CGFloat = 64
        let bar = CGRect(x: rect.midX - barW / 2, y: rect.midY - barH / 2, width: barW, height: barH)
        ctx.setFillColor(BlomixAppearance.emptyCell.cgColor)
        ctx.fill(bar)
        ctx.setStrokeColor(BlomixAppearance.chipBorder.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(bar)
        let fillH = barH * 0.36
        let fill = CGRect(x: bar.minX, y: bar.maxY - fillH, width: barW, height: fillH)
        ctx.setFillColor(BlomixAppearance.primaryText.cgColor)
        ctx.fill(fill)
    }
}

/// Mini-scène Bombe / Magix : le corps shader n’est créé que lorsque la taille est réelle.
@MainActor
private final class GuideSpritePreviewScene: SKScene {
    private let previewKind: BlomixGuideIllustrationKind
    private let magixKind: MagixKind
    private var sprite: SKSpriteNode?
    private var installedForSide: CGFloat = 0

    init(kind: BlomixGuideIllustrationKind, magixKind: MagixKind) {
        self.previewKind = kind
        self.magixKind = magixKind
        super.init(size: CGSize(width: 120, height: 120))
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:)") }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(cgColor: BlomixAppearance.emptyCell.cgColor)
        installSpriteIfNeeded()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        installSpriteIfNeeded()
        sprite?.position = CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func installSpriteIfNeeded() {
        let available = min(size.width, size.height)
        guard available >= 24 else { return }
        if sprite != nil, abs(installedForSide - available) < 6 {
            sprite?.position = CGPoint(x: size.width / 2, y: size.height / 2)
            return
        }
        sprite?.removeFromParent()
        sprite = nil
        // Corps assez grand pour le dégradé ; un peu de marge pour le halo.
        let side = min(available * 0.70, 56)
        let node: SKSpriteNode
        if previewKind == .bombs {
            node = GameScene.makeGuideBombPreviewSprite(size: CGSize(width: side, height: side))
        } else {
            node = GameScene.makeGuideMagixPreviewSprite(size: CGSize(width: side, height: side), kind: magixKind)
        }
        node.zPosition = 2
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(node)
        sprite = node
        installedForSide = available
    }
}
