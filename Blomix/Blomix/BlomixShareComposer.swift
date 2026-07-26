//
//  BlomixShareComposer.swift
//  Blomix
//
//  Messages, lien App Store et carte image 1:1 pour le partage (accueil + game over).
//

import UIKit

/// Compose le contenu de la share sheet système (`UIActivityViewController`).
@MainActor
enum BlomixShareComposer {

    /// App Store ID (App Store Connect) — URL canonique sans locale forcée.
    static let appStoreID = "6762053543"
    static let appStoreURL = URL(string: "https://apps.apple.com/app/blomix/id\(appStoreID)")!

    // MARK: - Messages

    /// Message d'accueil : best Solo, sinon Zen, sinon invitation sans score.
    static func homeMessage() -> String {
        let solo = ScoreManager.shared.getLocalHighScore()
        let zen = ScoreManager.shared.getLocalZenHighScore()
        if solo > 0 {
            return BlomixL10n.shareHomeScore(formattedScore(solo))
        }
        if zen > 0 {
            return BlomixL10n.shareHomeScoreZen(formattedScore(zen))
        }
        return BlomixL10n.shareHomeNoScore
    }

    /// Message game over (run courante ; variante record si `isNewPB`).
    static func gameOverMessage(score: Int, isZen: Bool, isNewPB: Bool) -> String {
        let s = formattedScore(score)
        if isNewPB {
            return isZen ? BlomixL10n.shareGameOverRecordZen(s) : BlomixL10n.shareGameOverRecord(s)
        }
        return isZen ? BlomixL10n.shareGameOverScoreZen(s) : BlomixL10n.shareGameOverScore(s)
    }

    static func formattedScore(_ score: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        return f.string(from: NSNumber(value: score)) ?? "\(score)"
    }

    // MARK: - Activity items

    /// Accueil : texte + URL (pas d'image custom).
    static func homeActivityItems() -> [Any] {
        [homeMessage(), appStoreURL]
    }

    /// Game over : image carte + texte + URL.
    static func gameOverActivityItems(
        grid: [[BlockType]],
        score: Int,
        isZen: Bool,
        isNewPB: Bool,
        cardImage: UIImage?
    ) -> [Any] {
        var items: [Any] = []
        let image = cardImage ?? makeGameOverShareCard(
            grid: grid,
            score: score,
            isZen: isZen,
            isNewPB: isNewPB
        )
        items.append(image)
        items.append(gameOverMessage(score: score, isZen: isZen, isNewPB: isNewPB))
        items.append(appStoreURL)
        return items
    }

    // MARK: - Carte 1:1 (game over)

    /// Génère une carte carrée : titre, grille (skin + thème), score, badge record optionnel.
    static func makeGameOverShareCard(
        grid: [[BlockType]],
        score: Int,
        isZen: Bool,
        isNewPB: Bool,
        side: CGFloat = 1080
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let bg = BlomixAppearance.sceneBackground
        let primary = BlomixAppearance.primaryText
        let secondary = BlomixAppearance.secondaryText
        let emptyFill = BlomixAppearance.emptyCell
        let emptyStroke = BlomixAppearance.emptyCellStroke

        let rows = grid.count
        let cols = rows > 0 ? grid[0].count : 8
        let safeRows = max(rows, 1)
        let safeCols = max(cols, 1)

        return renderer.image { ctx in
            let c = ctx.cgContext

            // Fond thème
            bg.setFill()
            c.fill(CGRect(origin: .zero, size: size))

            // Titre BLOMIX
            let titleFont = titleUIFont(size: side * 0.055)
            let title = "BLOMIX" as NSString
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: primary,
            ]
            let titleSize = title.size(withAttributes: titleAttrs)
            let titleY = side * 0.055
            title.draw(
                at: CGPoint(x: (side - titleSize.width) / 2, y: titleY),
                withAttributes: titleAttrs
            )

            // Badge ZEN (seulement si Zen)
            if isZen {
                let badgeFont = titleUIFont(size: side * 0.028)
                let badge = "ZEN" as NSString
                let badgeAttrs: [NSAttributedString.Key: Any] = [
                    .font: badgeFont,
                    .foregroundColor: secondary,
                ]
                let badgeSize = badge.size(withAttributes: badgeAttrs)
                let padX: CGFloat = side * 0.018
                let padY: CGFloat = side * 0.008
                let badgeRect = CGRect(
                    x: side - badgeSize.width - padX * 2 - side * 0.05,
                    y: titleY + (titleSize.height - badgeSize.height - padY * 2) / 2,
                    width: badgeSize.width + padX * 2,
                    height: badgeSize.height + padY * 2
                )
                let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeRect.height / 2)
                BlomixAppearance.chipFill.setFill()
                badgePath.fill()
                BlomixAppearance.chipBorder.setStroke()
                badgePath.lineWidth = 1
                badgePath.stroke()
                badge.draw(
                    at: CGPoint(x: badgeRect.midX - badgeSize.width / 2, y: badgeRect.midY - badgeSize.height / 2),
                    withAttributes: badgeAttrs
                )
            }

            // Zone grille centrée
            let gridSide = side * 0.58
            let cell = gridSide / CGFloat(safeCols)
            let gridW = cell * CGFloat(safeCols)
            let gridH = cell * CGFloat(safeRows)
            let gridOrigin = CGPoint(
                x: (side - gridW) / 2,
                y: side * 0.16
            )

            // Cadre léger autour de la grille
            let framePad: CGFloat = cell * 0.12
            let frameRect = CGRect(
                x: gridOrigin.x - framePad,
                y: gridOrigin.y - framePad,
                width: gridW + framePad * 2,
                height: gridH + framePad * 2
            )
            let framePath = UIBezierPath(roundedRect: frameRect, cornerRadius: cell * 0.25)
            BlomixAppearance.chipFill.setFill()
            framePath.fill()

            let gap: CGFloat = max(1, cell * 0.06)
            let corner = max(2, cell * 0.14)

            for r in 0..<safeRows {
                for col in 0..<safeCols {
                    let block: BlockType
                    if r < grid.count, col < grid[r].count {
                        block = grid[r][col]
                    } else {
                        block = .empty
                    }
                    // row 0 = haut (comme le modèle jeu)
                    let x = gridOrigin.x + CGFloat(col) * cell + gap / 2
                    let y = gridOrigin.y + CGFloat(r) * cell + gap / 2
                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: cell - gap,
                        height: cell - gap
                    )
                    let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)

                    switch block {
                    case .color(let name):
                        let fill = BlomixSkinCatalog.shared.bloxUIColor(forNormalizedKey: name)
                            ?? UIColor(white: 0.45, alpha: 1)
                        fill.setFill()
                        path.fill()
                    case .priks(let n):
                        BlomixSkinCatalog.shared.priksUIColor().setFill()
                        path.fill()
                        let digit = "\(n)" as NSString
                        let dFont = titleUIFont(size: cell * 0.42)
                        let dAttrs: [NSAttributedString.Key: Any] = [
                            .font: dFont,
                            .foregroundColor: BlomixSkinCatalog.shared.priksDigitUIColor(),
                        ]
                        let dSize = digit.size(withAttributes: dAttrs)
                        digit.draw(
                            at: CGPoint(
                                x: rect.midX - dSize.width / 2,
                                y: rect.midY - dSize.height / 2
                            ),
                            withAttributes: dAttrs
                        )
                    case .magix(let kind):
                        UIColor(white: BlomixAppearance.isDark ? 0.82 : 0.72, alpha: 1).setFill()
                        path.fill()
                        let sym = magixSymbol(kind) as NSString
                        let mFont = titleUIFont(size: cell * 0.36)
                        let mAttrs: [NSAttributedString.Key: Any] = [
                            .font: mFont,
                            .foregroundColor: BlomixAppearance.isDark ? UIColor.black : UIColor.black.withAlphaComponent(0.75),
                        ]
                        let mSize = sym.size(withAttributes: mAttrs)
                        sym.draw(
                            at: CGPoint(
                                x: rect.midX - mSize.width / 2,
                                y: rect.midY - mSize.height / 2
                            ),
                            withAttributes: mAttrs
                        )
                    case .empty:
                        emptyFill.setFill()
                        path.fill()
                        emptyStroke.setStroke()
                        path.lineWidth = max(0.5, cell * 0.03)
                        path.stroke()
                    }
                }
            }

            // Score
            let scoreText = formattedScore(score) as NSString
            let scoreFont = titleUIFont(size: side * 0.09)
            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: scoreFont,
                .foregroundColor: primary,
            ]
            let scoreSize = scoreText.size(withAttributes: scoreAttrs)
            let scoreY = gridOrigin.y + gridH + side * 0.045
            scoreText.draw(
                at: CGPoint(x: (side - scoreSize.width) / 2, y: scoreY),
                withAttributes: scoreAttrs
            )

            // Bandeau nouveau record
            if isNewPB {
                let badgeText = BlomixL10n.shareCardRecordBadge as NSString
                let bFont = titleUIFont(size: side * 0.032)
                let bAttrs: [NSAttributedString.Key: Any] = [
                    .font: bFont,
                    .foregroundColor: UIColor.white,
                ]
                let bSize = badgeText.size(withAttributes: bAttrs)
                let padX = side * 0.028
                let padY = side * 0.012
                let badgeW = bSize.width + padX * 2
                let badgeH = bSize.height + padY * 2
                let badgeRect = CGRect(
                    x: (side - badgeW) / 2,
                    y: scoreY + scoreSize.height + side * 0.02,
                    width: badgeW,
                    height: badgeH
                )
                let accent = recordBadgeFillColor()
                let bPath = UIBezierPath(roundedRect: badgeRect, cornerRadius: badgeH / 2)
                accent.setFill()
                bPath.fill()
                badgeText.draw(
                    at: CGPoint(
                        x: badgeRect.midX - bSize.width / 2,
                        y: badgeRect.midY - bSize.height / 2
                    ),
                    withAttributes: bAttrs
                )
            }
        }
    }

    // MARK: - Private helpers

    private static func titleUIFont(size: CGFloat) -> UIFont {
        BlomixTypography.uiFont(size: size, weight: .regular)
    }

    private static func magixSymbol(_ kind: MagixKind) -> String {
        switch kind {
        case .chromax:  return "?"
        case .brixed:   return "9"
        case .crosx:    return "+"
        case .scrumblx: return "="
        case .colorx:   return "O"
        case .cleanx:   return "∞"
        case .twistx:   return "X"
        }
    }

    /// Vert succès lisible en sombre et clair.
    private static func recordBadgeFillColor() -> UIColor {
        if BlomixAppearance.isDark {
            return UIColor(red: 0.22, green: 0.68, blue: 0.40, alpha: 1)
        }
        return UIColor(red: 0.16, green: 0.55, blue: 0.32, alpha: 1)
    }
}
