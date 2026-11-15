//
//  BlomixTypography.swift
//  Blomix
//
//  Typo figée v6.1 — deux visages, plus de picker joueur.
//    display / grille : Changa One, ou Caveat Brush si le style visuel est Encre
//    chrome           : Nunito
//      Regular   — micro-captions (< 13 pt)
//      Medium    — corps (réglages, HUD, lobby)
//      SemiBold  — chrome hors boutons
//    boutons       : même visage que display — puits + capsule 6.7
//

import Foundation
import UIKit

enum BlomixTypeRole: Sendable {
    case display
    case chrome
    case grid

    /// Changa One. Encre : Caveat Brush, enregistrée à la main (`CaveatBrush-Regular`).
    static let changaPostScriptName = "ChangaOne"
    static let inkPostScriptName = "CaveatBrush-Regular"

    var postScriptName: String {
        switch self {
        case .display, .grid:
            return BlomixVisualStyle.current == .new ? Self.inkPostScriptName : Self.changaPostScriptName
        case .chrome:
            return "Nunito-Medium"
        }
    }
}

@MainActor
final class BlomixTypography {
    static let shared = BlomixTypography()

    private init() {}

    static func fontName(_ role: BlomixTypeRole) -> String {
        role.postScriptName
    }

    var displayFontName: String { BlomixTypeRole.display.postScriptName }
    var chromeFontName: String { BlomixTypeRole.chrome.postScriptName }
    var gridFontName: String { BlomixTypeRole.grid.postScriptName }

    /// Alias historique → chrome Medium (corps).
    var spriteKitFontName: String { chromeFontName }

    /// PostScript Nunito selon taille / graisse.
    static func chromePostScriptName(size: CGFloat, weight: UIFont.Weight = .regular) -> String {
        if size < 13 { return "Nunito-Regular" }
        if weight >= .semibold { return "Nunito-SemiBold" }
        return "Nunito-Medium"
    }

    func uiFont(role: BlomixTypeRole, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let name: String
        switch role {
        case .chrome:
            name = Self.chromePostScriptName(size: size, weight: weight)
        case .display, .grid:
            name = role.postScriptName
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        uiFont(role: .chrome, size: size, weight: weight)
    }

    static func uiFont(role: BlomixTypeRole, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        shared.uiFont(role: role, size: size, weight: weight)
    }

    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        shared.uiFont(size: size, weight: weight)
    }

    static func displayFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        uiFont(role: .display, size: size, weight: weight)
    }

    static func chromeFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        uiFont(role: .chrome, size: size, weight: weight)
    }

    static func gridFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        uiFont(role: .grid, size: size, weight: weight)
    }
}
