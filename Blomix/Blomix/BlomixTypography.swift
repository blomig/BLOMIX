//
//  BlomixTypography.swift
//  Blomix
//
//  Gestion centralisée de la police choisie par le joueur.
//

import Foundation
import UIKit

extension Notification.Name {
    static let blomixFontDidChange = Notification.Name("blomixFontDidChange")
}

enum BlomixFontChoice: String, CaseIterable, Sendable {
    case bitcount
    case googleSans
    case dynaPuff
    case alfaSlabOne
    case changaOne

    var postScriptName: String {
        switch self {
        case .bitcount:    return "BitcountGridSingleInk-Regular"
        case .googleSans:  return "GoogleSans-Regular"
        case .dynaPuff:    return "DynaPuff-Regular"
        case .alfaSlabOne: return "AlfaSlabOne-Regular"
        case .changaOne:   return "ChangaOne"
        }
    }

    var fileName: String {
        switch self {
        case .bitcount:    return "BitcountGridSingleInk-Variable.ttf"
        case .googleSans:  return "GoogleSans-Regular.ttf"
        case .dynaPuff:    return "DynaPuff-Regular.ttf"
        case .alfaSlabOne: return "AlfaSlabOne-Regular.ttf"
        case .changaOne:   return "ChangaOne-Regular.ttf"
        }
    }
}

@MainActor
final class BlomixTypography {
    static let shared = BlomixTypography()

    private enum Persistence {
        static let selectedFontIDKey = "BlomixSelectedFontID"
    }

    private init() {}

    func allChoices() -> [BlomixFontChoice] {
        BlomixFontChoice.allCases
    }

    var selectedFontChoice: BlomixFontChoice {
        get {
            let raw = UserDefaults.standard.string(forKey: Persistence.selectedFontIDKey)
            return raw.flatMap(BlomixFontChoice.init(rawValue:)) ?? .bitcount
        }
        set {
            guard selectedFontChoice != newValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: Persistence.selectedFontIDKey)
            NotificationCenter.default.post(name: .blomixFontDidChange, object: nil)
        }
    }

    var spriteKitFontName: String {
        selectedFontChoice.postScriptName
    }

    func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        UIFont(name: spriteKitFontName, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    func fontDisplayName(for choice: BlomixFontChoice) -> String {
        switch choice {
        case .bitcount:    return BlomixL10n.settingsFontNameBitcount
        case .googleSans:  return BlomixL10n.settingsFontNameGoogleSans
        case .dynaPuff:    return BlomixL10n.settingsFontNameDynaPuff
        case .alfaSlabOne: return BlomixL10n.settingsFontNameAlfaSlabOne
        case .changaOne:   return BlomixL10n.settingsFontNameChangaOne
        }
    }

    static func uiFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        shared.uiFont(size: size, weight: weight)
    }
}
