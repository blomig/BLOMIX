//
//  BlomixUIButtonStyle.swift
//  Blomix
//
//  Style commun des boutons UIKit « navigation » (fermer, autre écran, etc.) : police choisie, blanc, fond #232323, bordure 1 px #444444.
//  Même rendu pour les chips SpriteKit (écran d’accueil).
//

import SpriteKit
import UIKit

@MainActor
enum BlomixUIDestinationButtonStyle {
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

    /// Épaisseur d’une ligne de 1 pixel physique (comme en CSS).
    static var hairlineBorderWidth: CGFloat {
        1.0 / max(UIScreen.main.scale, 1)
    }

    /// Taille unique pour tous les boutons de navigation (comme « Fermer ») + pastilles d’accueil SpriteKit.
    static let navigationTitleFontSize: CGFloat = 17

    static func titleFont(size: CGFloat, weight: UIFont.Weight = .medium) -> UIFont {
        BlomixTypography.uiFont(size: size, weight: weight)
    }

    /// Même style que le bouton Fermer : `navigationTitleFontSize` + poids au choix.
    static func applyNavigationButtonStyle(to button: UIButton, weight: UIFont.Weight = .medium, cornerRadius: CGFloat = 10) {
        apply(to: button, fontSize: navigationTitleFontSize, weight: weight, cornerRadius: cornerRadius)
    }

    /// Texte blanc, police choisie par le joueur, fond #232323, bordure 1 px #444444 ; `clipsToBounds` pour les coins arrondis.
    static func apply(to button: UIButton, fontSize: CGFloat, weight: UIFont.Weight = .medium, cornerRadius: CGFloat = 10) {
        if #available(iOS 15.0, *) {
            button.configuration = nil
        }
        button.setTitleColor(.white, for: .normal)
        button.tintColor = .white
        button.backgroundColor = backgroundColor
        button.titleLabel?.font = titleFont(size: fontSize, weight: weight)
        button.layer.cornerRadius = cornerRadius
        button.layer.borderWidth = hairlineBorderWidth
        button.layer.borderColor = borderColor.cgColor
        button.clipsToBounds = true
    }

    /// Fond #232323 pour `SKShapeNode` / pastilles d’accueil (aligné sur UIKit).
    static let startScreenChipFillSKColor = SKColor(cgColor: backgroundColor.cgColor)
}
