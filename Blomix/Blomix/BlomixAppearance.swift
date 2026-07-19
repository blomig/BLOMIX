//
//  BlomixAppearance.swift
//  Blomix
//
//  Thème chrome Sombre / Clair (orthogonal aux skins de couleurs des blox).
//  Défaut = sombre (= look historique du jeu).
//

import SpriteKit
import UIKit

// MARK: - Mode

enum BlomixAppearanceMode: String, CaseIterable {
    case dark
    case light

    var isDark: Bool { self == .dark }
    var isLight: Bool { self == .light }

    mutating func toggle() {
        self = isDark ? .light : .dark
    }
}

// MARK: - Notification

extension Notification.Name {
    /// Postée après changement de `BlomixAppearance.mode` (accueil reconstruit).
    static let blomixAppearanceDidChange = Notification.Name("blomixAppearanceDidChange")
}

// MARK: - Store + tokens

/// Tokens chrome — lecture OK hors MainActor (UserDefaults + couleurs pures).
/// Les changements passent par l'UI (accueil) ; la notification est postée sur le thread appelant.
enum BlomixAppearance {

    private static let defaultsKey = "BlomixAppearanceMode"

    /// Mode courant (manuel in-app ; ne suit pas le mode système iOS).
    static var mode: BlomixAppearanceMode {
        get {
            if let raw = UserDefaults.standard.string(forKey: defaultsKey),
               let m = BlomixAppearanceMode(rawValue: raw) {
                return m
            }
            return .dark
        }
        set {
            let old = mode
            guard newValue != old else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: .blomixAppearanceDidChange, object: nil)
        }
    }

    static var isDark: Bool { mode.isDark }
    static var isLight: Bool { mode.isLight }

    static func toggle() {
        var m = mode
        m.toggle()
        mode = m
    }

    // MARK: - Tokens UIColor

    /// Fond plein écran / scènes / modales.
    static var sceneBackground: UIColor {
        isDark ? .black : UIColor(hexRGB: 0xF5EEDF)
    }

    static var primaryText: UIColor {
        isDark ? .white : UIColor(white: 0.15, alpha: 1)
    }

    /// Popups flottants de score / feedback gameplay (+N, Magix, dots par défaut).
    /// Blanc en Sombre, gris très foncé en Clair (`primaryText`).
    static var floatingScoreAccent: UIColor { primaryText }
    static var floatingScoreAccentSK: SKColor { primaryTextSK }

    static var secondaryText: UIColor {
        isDark ? UIColor(white: 0.82, alpha: 1) : UIColor(white: 0.35, alpha: 1)
    }

    static var tertiaryText: UIColor {
        isDark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.48, alpha: 1)
    }

    static var linkText: UIColor {
        isDark ? UIColor(white: 0.55, alpha: 1) : UIColor(white: 0.40, alpha: 1)
    }

    static var separatorText: UIColor {
        isDark ? UIColor(white: 0.38, alpha: 1) : UIColor(white: 0.62, alpha: 1)
    }

    /// Pastilles boutons (repos).
    static var chipFill: UIColor {
        isDark
            ? UIColor(hexRGB: 0x232323)
            : UIColor(hexRGB: 0xE8E0D0)
    }

    static var chipBorder: UIColor {
        isDark
            ? UIColor(hexRGB: 0x444444)
            : UIColor(hexRGB: 0xC4BBA8)
    }

    static var chipTitle: UIColor {
        isDark ? .white : UIColor(white: 0.15, alpha: 1)
    }

    /// Pastilles à l'état appuyé.
    static var chipPressedFill: UIColor {
        isDark
            ? UIColor(hexRGB: 0x2D2D2D)
            : UIColor(hexRGB: 0xDDD4C2)
    }

    static var chipShadowOpacity: Float {
        isDark ? 0.40 : 0.18
    }

    static var skChipShadowAlpha: CGFloat {
        isDark ? 0.28 : 0.14
    }

    /// Couleur de l’ombre portée des chips.
    /// Sombre : gris clair (le noir est invisible sur fond noir) ; Clair : noir inchangé.
    static var chipShadowColor: UIColor {
        isDark ? UIColor(white: 0.65, alpha: 1) : .black
    }

    /// Remplissage ombre SpriteKit (couleur + alpha déjà combinés).
    static var skChipShadowFill: UIColor {
        chipShadowColor.withAlphaComponent(skChipShadowAlpha)
    }

    /// Cases vides de la grille / file upcoming.
    /// Clair : un cran sous le fond `#F5EEDF` (sans y coller) pour garder le relief des cases.
    static var emptyCell: UIColor {
        isDark
            ? UIColor(white: 0.12, alpha: 1)
            : UIColor(hexRGB: 0xEBE3D0)
    }

    /// Contour léger des cases vides (grille pire coup, etc.).
    static var emptyCellStroke: UIColor {
        isDark
            ? UIColor(white: 0.22, alpha: 1)
            : UIColor(white: 0, alpha: 0.12)
    }

    /// Surbrillance colonne de visée (appui long / ghost drop).
    /// Sombre : ~#444 ; Clair : gris beige plus clair, lisible sur les cases `#EBE3D0`.
    static var ghostColumnHighlight: UIColor {
        isDark
            ? UIColor(white: 0.267, alpha: 0.9)
            : UIColor(hexRGB: 0xD4CBB4).withAlphaComponent(0.92)
    }

    static var ghostColumnHighlightSK: SKColor { SKColor(cgColor: ghostColumnHighlight.cgColor) }

    /// Contour des labels de transition (stage / Zen / PvP / tutoriel) — fill orange skin inchangé.
    /// Sombre : blanc ; Clair : gris très foncé (lisible sur `#F5EEDF`).
    /// Pas de halo : la lisibilité repose uniquement sur ce contour.
    static var transitionOutlineColor: UIColor {
        isDark ? .white : UIColor(white: 0.12, alpha: 1)
    }

    /// Couleur du voile dim (alpha appliqué sur le nœud via `dimOverlayNodeAlpha`).
    static var dimOverlay: UIColor { .black }

    /// Alpha typique des voiles plein écran (quit, etc.).
    static var dimOverlayNodeAlpha: CGFloat { isDark ? 0.72 : 0.42 }

    /// Voile game over / pire coup.
    /// Sombre : noir ; Clair : beige de scène `#F5EEDF`.
    static var gameOverDimColor: UIColor {
        isDark ? .black : UIColor(hexRGB: 0xF5EEDF)
    }

    static var gameOverDimColorSK: SKColor { SKColor(cgColor: gameOverDimColor.cgColor) }

    /// Alpha du voile — Clair quasi opaque pour lisibilité des textes foncés.
    static var gameOverDimAlpha: CGFloat { isDark ? 0.72 : 0.94 }

    /// Alpha un peu plus fort pour le pire coup (même logique jour/nuit).
    static var worstMoveDimAlpha: CGFloat { isDark ? 0.88 : 0.94 }

    /// Textes game over / pire coup — clairs sur noir (Sombre), foncés sur beige (Clair).
    static var gameOverPrimaryText: UIColor { isDark ? .white : primaryText }
    static var gameOverPrimaryTextSK: SKColor { SKColor(cgColor: gameOverPrimaryText.cgColor) }
    static var gameOverSecondaryText: UIColor {
        isDark ? UIColor(white: 0.86, alpha: 1) : secondaryText
    }
    static var gameOverSecondaryTextSK: SKColor { SKColor(cgColor: gameOverSecondaryText.cgColor) }
    static var gameOverTertiaryText: UIColor {
        isDark ? UIColor(white: 0.60, alpha: 1) : tertiaryText
    }
    static var gameOverTertiaryTextSK: SKColor { SKColor(cgColor: gameOverTertiaryText.cgColor) }

    /// Track / séparateur du récap analyse sur game over.
    static var gameOverBarTrack: UIColor {
        isDark ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0, alpha: 0.08)
    }
    static var gameOverBarTrackSK: SKColor { SKColor(cgColor: gameOverBarTrack.cgColor) }
    static var gameOverBarBorder: UIColor {
        isDark
            ? UIColor(red: 0.878, green: 0.878, blue: 0.878, alpha: 0.65)
            : chipBorder.withAlphaComponent(0.85)
    }
    static var gameOverBarBorderSK: SKColor { SKColor(cgColor: gameOverBarBorder.cgColor) }
    static var gameOverSeparator: UIColor {
        isDark ? UIColor(white: 1, alpha: 0.22) : UIColor(white: 0, alpha: 0.12)
    }
    static var gameOverSeparatorSK: SKColor { SKColor(cgColor: gameOverSeparator.cgColor) }

    // Alias historiques (pire coup / overlays) → tokens game over.
    static var onDarkOverlayPrimaryText: UIColor { gameOverPrimaryText }
    static var onDarkOverlayPrimaryTextSK: SKColor { gameOverPrimaryTextSK }
    static var onDarkOverlaySecondaryText: UIColor { gameOverSecondaryText }
    static var onDarkOverlaySecondaryTextSK: SKColor { gameOverSecondaryTextSK }
    static var onDarkOverlayTertiaryText: UIColor { gameOverTertiaryText }
    static var onDarkOverlayTertiaryTextSK: SKColor { gameOverTertiaryTextSK }

    /// Alpha des voiles plus légers (transitions).
    static var dimOverlaySoftAlpha: CGFloat { isDark ? 0.52 : 0.32 }

    static var panelFill: UIColor {
        isDark
            ? UIColor(white: 0.10, alpha: 1)
            : UIColor(hexRGB: 0xEFE6D4)
    }

    static var panelFillTranslucent: UIColor {
        isDark
            ? UIColor(white: 0.08, alpha: 0.94)
            : UIColor(hexRGB: 0xEFE6D4).withAlphaComponent(0.96)
    }

    /// Bordure des boîtes de dialogue (tuto, etc.).
    static var panelStroke: UIColor {
        isDark
            ? UIColor(white: 1, alpha: 0.18)
            : UIColor(white: 0, alpha: 0.14)
    }

    static var panelStrokeStrong: UIColor {
        isDark
            ? UIColor(white: 1, alpha: 0.28)
            : UIColor(white: 0, alpha: 0.20)
    }

    static var tableRowHighlight: UIColor {
        isDark
            ? UIColor(white: 0.16, alpha: 1)
            : UIColor(white: 0.90, alpha: 1)
    }

    static var progressTrack: UIColor {
        isDark
            ? UIColor(white: 0.20, alpha: 1)
            : UIColor(white: 0.72, alpha: 1)
    }

    static var progressFill: UIColor {
        isDark
            ? UIColor(hexRGB: 0xADADAD)
            : UIColor(white: 0.42, alpha: 1)
    }

    /// Halo Magix / bombes / disques de rang.
    static var specialHalo: UIColor {
        isDark ? .white : .black
    }

    static var specialHaloBaseAlpha: CGFloat {
        isDark ? 0.45 : 0.22
    }

    static var specialHaloPulseHigh: CGFloat {
        isDark ? 0.55 : 0.32
    }

    static var specialHaloPulseLow: CGFloat {
        isDark ? 0.28 : 0.12
    }

    static var rankDiscHaloBaseAlpha: CGFloat {
        isDark ? 0.40 : 0.20
    }

    static var rankDiscHaloPulseHigh: CGFloat {
        isDark ? 0.55 : 0.30
    }

    static var rankDiscHaloPulseLow: CGFloat {
        isDark ? 0.22 : 0.10
    }

    static var statusBarStyle: UIStatusBarStyle {
        isDark ? .lightContent : .darkContent
    }

    // MARK: - SKColor convenience

    static var sceneBackgroundSK: SKColor { SKColor(cgColor: sceneBackground.cgColor) }
    static var primaryTextSK: SKColor { SKColor(cgColor: primaryText.cgColor) }
    static var secondaryTextSK: SKColor { SKColor(cgColor: secondaryText.cgColor) }
    static var tertiaryTextSK: SKColor { SKColor(cgColor: tertiaryText.cgColor) }
    static var linkTextSK: SKColor { SKColor(cgColor: linkText.cgColor) }
    static var separatorTextSK: SKColor { SKColor(cgColor: separatorText.cgColor) }
    static var chipFillSK: SKColor { SKColor(cgColor: chipFill.cgColor) }
    static var chipBorderSK: SKColor { SKColor(cgColor: chipBorder.cgColor) }
    static var chipTitleSK: SKColor { SKColor(cgColor: chipTitle.cgColor) }
    static var chipShadowColorSK: SKColor { SKColor(cgColor: chipShadowColor.cgColor) }
    static var skChipShadowFillSK: SKColor { SKColor(cgColor: skChipShadowFill.cgColor) }
    static var chipPressedFillSK: SKColor { SKColor(cgColor: chipPressedFill.cgColor) }
    static var emptyCellSK: SKColor { SKColor(cgColor: emptyCell.cgColor) }
    static var emptyCellStrokeSK: SKColor { SKColor(cgColor: emptyCellStroke.cgColor) }
    static var dimOverlaySK: SKColor { SKColor(cgColor: dimOverlay.cgColor) }
    static var panelFillSK: SKColor { SKColor(cgColor: panelFill.cgColor) }
    static var progressTrackSK: SKColor { SKColor(cgColor: progressTrack.cgColor) }
    static var progressFillSK: SKColor { SKColor(cgColor: progressFill.cgColor) }
    static var specialHaloSK: SKColor { SKColor(cgColor: specialHalo.cgColor) }

    // MARK: - SF Symbol helper (toggle accueil)

    /// Texture soleil (mode sombre → propose Clair) ou lune (mode clair → propose Sombre).
    /// Rasterisée via UIGraphics (comme l'icône menu) : un SF Symbol brut en SKTexture
    /// apparaît souvent noir/invisible selon le chemin de rendu SpriteKit.
    static func appearanceToggleTexture(pointSize: CGFloat = 22, canvasSide: CGFloat = 32) -> SKTexture {
        let symbolName = isDark ? "sun.max.fill" : "moon.fill"
        let glyph = primaryText
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let base = UIImage(systemName: symbolName, withConfiguration: config)
            ?? UIImage(systemName: "circle.fill", withConfiguration: config)
            ?? UIImage()
        let sym = base.withTintColor(glyph, renderingMode: .alwaysOriginal)

        let imgSize = CGSize(width: canvasSide, height: canvasSide)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let flat = UIGraphicsImageRenderer(size: imgSize, format: format).image { _ in
            // Centrer le glyphe dans le canvas.
            let aspect = sym.size.width / max(sym.size.height, 1)
            let drawH = canvasSide * 0.78
            let drawW = drawH * aspect
            let rect = CGRect(
                x: (canvasSide - drawW) / 2,
                y: (canvasSide - drawH) / 2,
                width: drawW,
                height: drawH
            )
            sym.draw(in: rect)
        }
        let tex = SKTexture(image: flat)
        tex.filteringMode = .linear
        return tex
    }
}

// MARK: - Hex helper

private extension UIColor {
    convenience init(hexRGB: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hexRGB >> 16) & 0xff) / 255
        let g = CGFloat((hexRGB >> 8) & 0xff) / 255
        let b = CGFloat(hexRGB & 0xff) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
