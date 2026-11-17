//
//  BlomixTypography.swift
//  Blomix
//
//  Typo figée v6.1 — deux associations, plus de picker joueur.
//    Classique : Changa One (display / grille) + Nunito (chrome)
//    Encre     : Chelsea Market (display / grille) + Pangolin (chrome)
//    Nunito
//      Regular   — micro-captions (< 13 pt)
//      Medium    — corps (réglages, HUD, lobby)
//      SemiBold  — chrome hors boutons
//    Pangolin n’a qu’un Regular : les trois graisses du chrome Encre l’utilisent.
//    boutons       : même visage que display — puits + capsule 6.7
//

import Foundation
import UIKit

enum BlomixTypeRole: Sendable {
    case display
    case chrome
    case grid

    /// Changa One. Encre : Chelsea Market, enregistrée à la main (`ChelseaMarket-Regular`).
    static let changaPostScriptName = "ChangaOne"
    static let inkPostScriptName = "ChelseaMarket-Regular"
    /// Nunito. Encre : Pangolin Regular, enregistrée à la main.
    static let nunitoRegularPostScriptName = "Nunito-Regular"
    static let nunitoMediumPostScriptName = "Nunito-Medium"
    static let nunitoSemiBoldPostScriptName = "Nunito-SemiBold"
    static let inkChromePostScriptName = "Pangolin-Regular"

    static var usesInkFaces: Bool { BlomixVisualStyle.current == .new }

    var postScriptName: String {
        switch self {
        case .display, .grid:
            return Self.usesInkFaces ? Self.inkPostScriptName : Self.changaPostScriptName
        case .chrome:
            return Self.usesInkFaces ? Self.inkChromePostScriptName : Self.nunitoMediumPostScriptName
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

    /// Classique : Nunito selon taille / graisse. Encre : Pangolin Regular.
    static func chromePostScriptName(size: CGFloat, weight: UIFont.Weight = .regular) -> String {
        if BlomixTypeRole.usesInkFaces { return BlomixTypeRole.inkChromePostScriptName }
        if size < 13 { return BlomixTypeRole.nunitoRegularPostScriptName }
        if weight >= .semibold { return BlomixTypeRole.nunitoSemiBoldPostScriptName }
        return BlomixTypeRole.nunitoMediumPostScriptName
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
